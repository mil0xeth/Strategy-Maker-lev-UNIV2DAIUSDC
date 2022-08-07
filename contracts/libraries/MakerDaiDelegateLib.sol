// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../../interfaces/maker/IMaker.sol";
import "../../interfaces/UniswapInterfaces/IUniswapV2Router02.sol";
import "../../interfaces/UniswapInterfaces/IUniswapV2Pair.sol";

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


//OSM
import "../../interfaces/yearn/IOSMedianizer.sol";

interface PSMLike {
    function gemJoin() external view returns (address);
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
}

interface IERC3156FlashLender {
    function maxFlashLoan(
        address token
    ) external view returns (uint256);
    function flashFee(
        address token,
        uint256 amount
    ) external view returns (uint256);
    function flashLoan(
        //IERC3156FlashBorrower receiver,
        address receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

interface IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

library MakerDaiDelegateLib {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //event DebugDelegate(uint256 _number, uint _value);

    enum Action {WIND, UNWIND}

    //uint256 public constant otherTokenTo18Conversion = 10 ** (18 - _otherToken.decimals());
    //Strategy specific addresses:
    //dai:
    IERC20 internal constant want = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant otherToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint256 public constant otherTokenTo18Conversion = 10 ** 12;
    //usdc:
    //IERC20 internal constant want = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    //IERC20 internal constant otherToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    //uint256 public constant otherTokenTo18Conversion = 1;

    //UNIV2DAIUSDC - UniswapV2 DAI/USDC LP
    IUniswapV2Pair internal constant yieldBearing = IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    bytes32 internal constant ilk_yieldBearing = 0x554e495632444149555344432d41000000000000000000000000000000000000;
    address internal constant gemJoinAdapter = 0xA81598667AC561986b70ae11bBE2dd5348ed4327;

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);    

    PSMLike public constant psm = PSMLike(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A) ;

    IERC20 internal constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    //MAKER Flashmint:
    IERC3156FlashLender public constant flashmint = IERC3156FlashLender(0x1EB4CF3A948E7D72A198fe073cCb8C7a948cD853);

    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // Do not attempt to mint DAI if there are less than MIN_MINTABLE available. Used to be 500kDAI --> reduced to 50kDAI
    uint256 internal constant MIN_MINTABLE = 50000 * WAD;

    // Maker vaults manager
    ManagerLike internal constant manager = ManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);

    // Token Adapter Module for collateral
    DaiJoinLike internal constant daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);

    // Liaison between oracles and core Maker contracts
    SpotLike internal constant spotter = SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);

    // Part of the Maker Rates Module in charge of accumulating stability fees
    JugLike internal constant jug = JugLike(0x19c0976f590D67707E62397C87829d896Dc0f1F1);

    // Debt Ceiling Instant Access Module
    DssAutoLine internal constant autoLine = DssAutoLine(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);

    // ----------------- PUBLIC FUNCTIONS -----------------

    // Creates an UrnHandler (cdp) for a specific ilk and allows to manage it via the internal
    // registry of the manager.
    function openCdp(bytes32 ilk) public returns (uint256) {
        return manager.open(ilk, address(this));
    }

    // Moves cdpId collateral balance and debt to newCdpId.
    function shiftCdp(uint256 cdpId, uint256 newCdpId) public {
        manager.shift(cdpId, newCdpId);
    }

    // Transfers the ownership of cdp to recipient address in the manager registry.
    function transferCdp(uint256 cdpId, address recipient) public {
        manager.give(cdpId, recipient);
    }

    // Allow/revoke manager access to a cdp
    function allowManagingCdp(
        uint256 cdpId,
        address user,
        bool isAccessGranted
    ) public {
        manager.cdpAllow(cdpId, user, isAccessGranted ? 1 : 0);
    }

    // Deposits collateral (gem) and mints DAI
    function lockGemAndDraw(
        address gemJoin,
        uint256 cdpId,
        uint256 collateralAmount,
        uint256 daiToMint,
        uint256 totalDebt
    ) public {
        address urn = manager.urns(cdpId);
        VatLike vat = VatLike(manager.vat());
        bytes32 ilk = manager.ilks(cdpId);

        if (daiToMint > 0) {
            daiToMint = _forceMintWithinLimits(vat, ilk, daiToMint, totalDebt);
        }

        // Takes token amount from the strategy and joins into the vat
        if (collateralAmount > 0) {
            GemJoinLike(gemJoin).join(urn, collateralAmount);
        }

        // Locks token amount into the CDP and generates debt
        manager.frob(
            cdpId,
            int256(convertTo18(gemJoin, collateralAmount)),
            _getDrawDart(vat, urn, ilk, daiToMint)
        );

        // Moves the DAI amount to the strategy. Need to convert dai from [wad] to [rad]
        manager.move(cdpId, address(this), daiToMint.mul(1e27));

        // Allow access to DAI balance in the vat
        vat.hope(address(daiJoin));

        // Exits DAI to the user's wallet as a token
        daiJoin.exit(address(this), daiToMint);
    }

    // Returns DAI to decrease debt and attempts to unlock any amount of collateral
    function wipeAndFreeGem(
        address gemJoin,
        uint256 cdpId,
        uint256 collateralAmount,
        uint256 daiToRepay
    ) public {
        address urn = manager.urns(cdpId);

        // Joins DAI amount into the vat
        if (daiToRepay > 0) {
            daiJoin.join(urn, daiToRepay);
        }

        uint256 wadC = convertTo18(gemJoin, collateralAmount);

        // Paybacks debt to the CDP and unlocks token amount from it
        manager.frob(
            cdpId,
            -int256(wadC),
            _getWipeDart(
                VatLike(manager.vat()),
                VatLike(manager.vat()).dai(urn),
                urn,
                manager.ilks(cdpId)
            )
        );

        // Moves the amount from the CDP urn to proxy's address
        manager.flux(cdpId, address(this), collateralAmount);

        // Exits token amount to the strategy as a token
        GemJoinLike(gemJoin).exit(address(this), collateralAmount);
    }

    function debtFloor(bytes32 ilk) public view returns (uint256) {
        // uint256 Art;   // Total Normalised Debt     [wad]
        // uint256 rate;  // Accumulated Rates         [ray]
        // uint256 spot;  // Price with Safety Margin  [ray]
        // uint256 line;  // Debt Ceiling              [rad]
        // uint256 dust;  // Urn Debt Floor            [rad]
        (, , , , uint256 dust) = VatLike(manager.vat()).ilks(ilk);
        return dust.div(RAY);
    }

    function debtForCdp(uint256 cdpId, bytes32 ilk)
        public
        view
        returns (uint256)
    {
        address urn = manager.urns(cdpId);
        VatLike vat = VatLike(manager.vat());

        // Normalized outstanding stablecoin debt [wad]
        (, uint256 art) = vat.urns(ilk, urn);

        // Gets actual rate from the vat [ray]
        (, uint256 rate, , , ) = vat.ilks(ilk);

        // Return the present value of the debt with accrued fees
        return art.mul(rate).div(RAY);
    }

    function balanceOfCdp(uint256 cdpId, bytes32 ilk)
        public
        view
        returns (uint256)
    {
        address urn = manager.urns(cdpId);
        VatLike vat = VatLike(manager.vat());

        (uint256 ink, ) = vat.urns(ilk, urn);
        return ink;
    }

    // Returns value of DAI in the reference asset (e.g. $1 per DAI)
    function getDaiPar() public view returns (uint256) {
        // Value is returned in ray (10**27)
        return spotter.par();
    }

    // Liquidation ratio for the given ilk returned in [ray]
    function getLiquidationRatio(bytes32 ilk) public view returns (uint256) {
        (, uint256 liquidationRatio) = spotter.ilks(ilk);
        return liquidationRatio;
    }

    function getSpotPrice(bytes32 ilk) public view returns (uint256) {
        VatLike vat = VatLike(manager.vat());

        // spot: collateral price with safety margin returned in [ray]
        (, , uint256 spot, , ) = vat.ilks(ilk);

        uint256 liquidationRatio = getLiquidationRatio(ilk);

        // convert ray*ray to wad
        return spot.mul(liquidationRatio).div(RAY * 1e9);
    }

    function getPessimisticRatioOfCdpWithExternalPrice(
        uint256 cdpId,
        bytes32 ilk,
        uint256 externalPrice,
        uint256 collateralizationRatioPrecision
    ) public view returns (uint256) {
        // Use pessimistic price to determine the worst ratio possible
        uint256 price = Math.min(getSpotPrice(ilk), externalPrice);
        require(price > 0); // dev: invalid price

        uint256 totalCollateralValue = balanceOfCdp(cdpId, ilk).mul(price).div(WAD);
        uint256 totalDebt = debtForCdp(cdpId, ilk);

        // If for some reason we do not have debt (e.g: deposits under dust)
        // make sure the operation does not revert
        if (totalDebt == 0) {
            totalDebt = 1;
        }

        return totalCollateralValue.mul(collateralizationRatioPrecision).div(totalDebt);
    }

    // Make sure we update some key content in Maker contracts
    // These can be updated by anyone without authenticating
    function keepBasicMakerHygiene(bytes32 ilk) public {
        // Update accumulated stability fees
        jug.drip(ilk);

        // Update the debt ceiling using DSS Auto Line
        autoLine.exec(ilk);
    }

    function daiJoinAddress() public view returns (address) {
        return address(daiJoin);
    }

    // Checks if there is at least MIN_MINTABLE dai available to be minted
    function isDaiAvailableToMint(bytes32 ilk) public view returns (bool) {
        return balanceOfDaiAvailableToMint(ilk) >= MIN_MINTABLE;
    }

    
    // Checks amount of Dai mintable
    function balanceOfDaiAvailableToMint(bytes32 ilk) public view returns (uint256) {
        VatLike vat = VatLike(manager.vat());
        (uint256 Art, uint256 rate, , uint256 line, ) = vat.ilks(ilk);

        // Total debt in [rad] (wad * ray)
        uint256 vatDebt = Art.mul(rate);

        if (vatDebt >= line) {
            return 0;
        }

        return line.sub(vatDebt).div(RAY);
    }

    function wind(
        uint256 wantAmountInitial,
        uint256 targetCollateralizationRatio,
        uint256 cdpId
    ) public {
        wantAmountInitial = Math.min(wantAmountInitial, balanceOfWant());
        //Calculate how much borrowToken to mint to leverage up to targetCollateralizationRatio:
        uint256 flashloanAmount = wantAmountInitial.mul(RAY).div(targetCollateralizationRatio.mul(1e9).sub(RAY));
        //convert want to borrowToken:
        flashloanAmount = _convertWantAmountToBorrowToken(flashloanAmount);
        VatLike vat = VatLike(manager.vat());
        uint256 currentDebt = debtForCdp(cdpId, ilk_yieldBearing);
        flashloanAmount = Math.min(flashloanAmount, _forceMintWithinLimits(vat, ilk_yieldBearing, flashloanAmount, currentDebt));
        //Check if amount of dai to borrow is above debtFloor
        if ( (currentDebt.add(flashloanAmount)) <= debtFloor(ilk_yieldBearing).add(1e15)){
            return;
        }
        bytes memory data = abi.encode(Action.WIND, cdpId, wantAmountInitial, flashloanAmount, targetCollateralizationRatio); 
        _initFlashLoan(data, flashloanAmount);
    }
    
    function unwind(
        uint256 wantAmountRequested,
        uint256 targetCollateralizationRatio,
        uint256 cdpId
    ) public {
        if (balanceOfCdp(cdpId, ilk_yieldBearing) == 0){
            return;
        }
        //Paying off the full debt it's common to experience Vat/dust reverts: we circumvent this with add 1 Wei to the amount to be paid
        uint256 flashloanAmount = debtForCdp(cdpId, ilk_yieldBearing).add(1);
        bytes memory data = abi.encode(Action.UNWIND, cdpId, wantAmountRequested, flashloanAmount, targetCollateralizationRatio);
        //Always flashloan entire debt to pay off entire debt:
        _initFlashLoan(data, flashloanAmount);
    }

    function _wind(uint256 cdpId, uint256 flashloanRepayAmount, uint256 wantAmountInitial, uint256) public {
        //repayAmount includes any fees
        _swapWantToBorrowToken(wantAmountInitial);
        uint256 yieldBearingAmountToLock = _swapBorrowTokenToYieldBearing(balanceOfBorrowToken());
        //Check allowance to lock collateral 
        _checkAllowance(gemJoinAdapter, address(yieldBearing), yieldBearingAmountToLock);
        //Lock collateral and borrow dai to repay flashmint
        lockGemAndDraw(
            gemJoinAdapter,
            cdpId,
            yieldBearingAmountToLock,
            flashloanRepayAmount,
            debtForCdp(cdpId, ilk_yieldBearing)
        );
    }

    function _unwind(uint256 cdpId, uint256 flashloanRepayAmount, uint256 wantAmountRequested, uint256 targetCollateralizationRatio) public {
        //Repay entire debt, to then take debt again later:
        //Check allowance for repaying borrowToken Debt
        uint256 currentDebtPlusRounding = debtForCdp(cdpId, ilk_yieldBearing).add(1);
        _checkAllowance(daiJoinAddress(), address(borrowToken), currentDebtPlusRounding);
        wipeAndFreeGem(gemJoinAdapter, cdpId, balanceOfCdp(cdpId, ilk_yieldBearing), currentDebtPlusRounding);
        //All debt paid down, collateral unlocked
        //Calculate leverage+1 to know how much totalRequestedInYieldBearing to swap for borrowToken
        uint256 leveragePlusOne = (RAY.mul(WAD).div((targetCollateralizationRatio.mul(1e9).sub(RAY)))).add(WAD);
        uint256 totalRequestedInYieldBearing = wantAmountRequested.mul(leveragePlusOne).div(getWantPerYieldBearing());
        //Maximum of all yieldBearing can be requested
        totalRequestedInYieldBearing = Math.min(totalRequestedInYieldBearing, balanceOfYieldBearing());
        
        _swapYieldBearingToBorrowToken(totalRequestedInYieldBearing);
        //Want amount requested now in wallet

        //Lock collateral and borrow dai equivalent to amount given by targetCollateralizationRatio:
        uint256 yieldBearingBalance = balanceOfYieldBearing();
        uint256 borrowTokenAmountToMint = yieldBearingBalance.mul(getBorrowTokenPerYieldBearing()).div(targetCollateralizationRatio);
        //Check if amount of dai to borrow is above debtFloor. If not, swap everything to want and return.
        if ( borrowTokenAmountToMint <= debtFloor(ilk_yieldBearing).add(1e15)){
            _swapYieldBearingToBorrowToken(balanceOfYieldBearing());
            _swapBorrowTokenToWant(balanceOfBorrowToken().sub(flashloanRepayAmount));
            return;
        }
        //Make sure to always mint enough to repay the flashloan
        borrowTokenAmountToMint = Math.min(borrowTokenAmountToMint, flashloanRepayAmount);
        //Check allowance to lock collateral 
        _checkAllowance(gemJoinAdapter, address(yieldBearing), yieldBearingBalance);
        //Lock collateral and mint dai to repay flashmint
        lockGemAndDraw(
            gemJoinAdapter,
            cdpId,
            yieldBearingBalance,
            borrowTokenAmountToMint,
            debtForCdp(cdpId, ilk_yieldBearing)
        );
        _swapBorrowTokenToWant(balanceOfBorrowToken().sub(flashloanRepayAmount));
    }

    //get amount of want in Wei that is received for 1 yieldBearing
    function getWantPerYieldBearing() internal view returns (uint256){
        //The returned tuple contains (DAI amount, USDC amount) - for want=dai:
        (uint256 otherTokenUnderlyingBalance, uint256 wantUnderlyingBalance, ) = yieldBearing.getReserves();
        return wantUnderlyingBalance.add(otherTokenUnderlyingBalance.div(1e12)).mul(WAD).div(yieldBearing.totalSupply());
    }

    //get amount of borrowToken in Wei that is received for 1 yieldBearing
    function getBorrowTokenPerYieldBearing() internal view returns (uint256){
        //The returned tuple contains (DAI amount, USDC amount) - for want=dai:
        (uint256 borrowTokenUnderlyingBalance, uint256 otherTokenUnderlyingBalance, ) = yieldBearing.getReserves();
        return borrowTokenUnderlyingBalance.add(otherTokenUnderlyingBalance.mul(1e12)).mul(WAD).div(yieldBearing.totalSupply());
    }

    function balanceOfWant() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfYieldBearing() internal view returns (uint256) {
        return yieldBearing.balanceOf(address(this));
    }

    function balanceOfOtherToken() internal view returns (uint256) {
        return otherToken.balanceOf(address(this));
    }

    function balanceOfBorrowToken() internal view returns (uint256) {
        return borrowToken.balanceOf(address(this));
    }

    // ----------------- TOKEN CONVERSIONS -----------------

    uint256 public constant wantTo18Conversion = 1e12;

    function _convertBorrowTokenAmountToWant(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        //want=usdc:
        return _amount.div(wantTo18Conversion);
    }

    function _convertWantAmountToBorrowToken(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        //want=usdc:
        return _amount.mul(wantTo18Conversion);
    }

    // ----------------- INTERNAL FUNCTIONS -----------------

    function _initFlashLoan(bytes memory data, uint256 amount) internal {
        //Flashmint implementation:
        _checkAllowance(address(flashmint), address(borrowToken), amount);
        flashmint.flashLoan(address(this), address(borrowToken), amount, data);
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            //IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, type(uint256).max);
        }
    }

    function _swapBorrowTokenToYieldBearing(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        _amount = Math.min(_amount, balanceOfBorrowToken());
        (uint256 borrowTokenRatio, uint256 wantRatio, ) = yieldBearing.getReserves();
        borrowTokenRatio = borrowTokenRatio.mul(WAD).div(yieldBearing.totalSupply());
        wantRatio = wantRatio.mul(WAD).mul(wantTo18Conversion).div(yieldBearing.totalSupply());
        uint256 borrowTokenAmountForMint = _amount.mul(borrowTokenRatio).div(borrowTokenRatio + wantRatio);
        uint256 borrowTokenAmountToSwapToWantForMint = _amount.mul(wantRatio).div(borrowTokenRatio + wantRatio);
        //Swap through PSM borrowTokenAmountToSwapToWantForMint --> want
        _checkAllowance(address(psm), address(borrowToken), borrowTokenAmountToSwapToWantForMint);
        psm.buyGem(address(this), borrowTokenAmountToSwapToWantForMint.div(wantTo18Conversion));

        //Mint yieldBearing:
        borrowTokenAmountForMint = Math.min(borrowTokenAmountForMint, balanceOfBorrowToken());
        uint256 wantBalance = balanceOfWant();
        _checkAllowance(address(yieldBearing), address(borrowToken), borrowTokenAmountForMint);
        _checkAllowance(address(yieldBearing), address(want), wantBalance);      
        (,,uint256 mintAmount) = router.addLiquidity(address(borrowToken), address(want), borrowTokenAmountForMint, wantBalance, 0, 0, address(this), block.timestamp);
        return balanceOfYieldBearing();
    }

    function _swapYieldBearingToBorrowToken(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        //Burn the yieldBearing token to unlock DAI and USDC:
        uint256 yieldBearingAmountToBurn = Math.min(_amount, balanceOfYieldBearing());
        _checkAllowance(address(router), address(yieldBearing), yieldBearingAmountToBurn);
        router.removeLiquidity(address(borrowToken), address(want), yieldBearingAmountToBurn, 0, 0, address(this),block.timestamp);

        //Amount of want after burning:
        uint256 wantBalance = balanceOfWant();

        //Swap through PSM Want ---> BorrowToken: USDC-> DAI
        address psmGemJoin = psm.gemJoin();
        _checkAllowance(psmGemJoin, address(want), wantBalance);
        //sellGem means: USDC --> DAI, gotta approve USDC amount in 1e6, gotta sellGem amount in 1e6
        psm.sellGem(address(this), wantBalance);
    }

    function _swapWantToBorrowToken(uint256 _wantAmount) public {
        if (_wantAmount > 1000 && balanceOfWant() >= _wantAmount){
            //Swap through PSM Want ---> BorrowToken: USDC-> DAI
            address psmGemJoin = psm.gemJoin();
            _checkAllowance(psmGemJoin, address(want), _wantAmount);
            //sellGem means: USDC --> DAI, gotta approve USDC amount in 1e6, gotta sellGem amount in 1e6
            psm.sellGem(address(this), _wantAmount);
        }
    }

    function _swapBorrowTokenToWant(uint256 _borrowTokenAmount) public {
        uint256 borrowTokenBalance = balanceOfBorrowToken();
        if (_borrowTokenAmount > 1000 && borrowTokenBalance >= _borrowTokenAmount){
            _checkAllowance(address(psm), address(borrowToken), _borrowTokenAmount);
            //buyGem means: DAI --> USDC, gotta approve DAI amount in 1e18, gotta buyGem amount in 1e6  
            psm.buyGem(address(this), _borrowTokenAmount.div(wantTo18Conversion));
        }
    }

    // This function repeats some code from daiAvailableToMint because it needs
    // to handle special cases such as not leaving debt under dust
    function _forceMintWithinLimits(
        VatLike vat,
        bytes32 ilk,
        uint256 desiredAmount,
        uint256 debtBalance
    ) internal view returns (uint256) {
        // uint256 Art;   // Total Normalised Debt     [wad]
        // uint256 rate;  // Accumulated Rates         [ray]
        // uint256 spot;  // Price with Safety Margin  [ray]
        // uint256 line;  // Debt Ceiling              [rad]
        // uint256 dust;  // Urn Debt Floor            [rad]
        (uint256 Art, uint256 rate, , uint256 line, uint256 dust) =
            vat.ilks(ilk);

        // Total debt in [rad] (wad * ray)
        uint256 vatDebt = Art.mul(rate);

        // Make sure we are not over debt ceiling (line) or under debt floor (dust)
        if (
            vatDebt >= line || (desiredAmount.add(debtBalance) <= dust.div(RAY))
        ) {
            return 0;
        }

        uint256 maxMintableDAI = line.sub(vatDebt).div(RAY);

        // Avoid edge cases with low amounts of available debt
        if (maxMintableDAI < MIN_MINTABLE) {
            return 0;
        }

        // Prevent rounding errors
        if (maxMintableDAI > WAD) {
            maxMintableDAI = maxMintableDAI - WAD;
        }

        return Math.min(maxMintableDAI, desiredAmount);
    }

    function _getDrawDart(
        VatLike vat,
        address urn,
        bytes32 ilk,
        uint256 wad
    ) internal returns (int256 dart) {
        // Updates stability fee rate
        uint256 rate = jug.drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint256 dai = vat.dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        if (dai < wad.mul(RAY)) {
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = int256(wad.mul(RAY).sub(dai).div(rate));
            // This is neeeded due to lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = uint256(dart).mul(rate) < wad.mul(RAY) ? dart + 1 : dart;
        }
    }

    function _getWipeDart(
        VatLike vat,
        uint256 dai,
        address urn,
        bytes32 ilk
    ) internal view returns (int256 dart) {
        // Gets actual rate from the vat
        (, uint256 rate, , , ) = vat.ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = vat.urns(ilk, urn);

        // Uses the whole dai balance in the vat to reduce the debt
        dart = int256(dai / rate);

        // Checks the calculated dart is not higher than urn.art (total debt), otherwise uses its value
        dart = uint256(dart) <= art ? -dart : -int256(art);
    }

    function convertTo18(address gemJoin, uint256 amt)
        internal
        returns (uint256 wad)
    {
        // For those collaterals that have less than 18 decimals precision we need to do the conversion before
        // passing to frob function
        // Adapters will automatically handle the difference of precision
        wad = amt.mul(10**(18 - GemJoinLike(gemJoin).dec()));
    }


}
