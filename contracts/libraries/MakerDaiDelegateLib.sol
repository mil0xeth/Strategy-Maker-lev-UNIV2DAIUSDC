// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../../interfaces/maker/IMaker.sol";
import "../../interfaces/UniswapInterfaces/IWETH.sol";
import "../../interfaces/lido/ISteth.sol";
import "../../interfaces/lido/IWstETH.sol";
import "../../interfaces/curve/Curve.sol";
import "../../interfaces/swap/ISwap.sol";

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


//DYDX FLashloan
import "../../interfaces/DyDx/ISoloMargin.sol";
//import "../../interfaces/DyDx/DydxFlashLoanBase.sol";
//import "../../interfaces/DyDx/ICallee.sol";
//AAVE Flashloan
import "../../interfaces/Aave/ILendingPoolAddressesProvider.sol";
import "../../interfaces/Aave/ILendingPool.sol";

//OSM
import "../../interfaces/yearn/IOSMedianizer.sol";

library MakerDaiDelegateLib {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event DebugDelegate(uint256 _number, uint _value);

    //Strategy specific addresses:
    IWstETH internal constant yieldBearing =  IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    bytes32 internal constant ilk_yieldBearing = 0x5753544554482d41000000000000000000000000000000000000000000000000;
    address internal constant gemJoinFlash = 0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2;
    ISteth internal constant stETH =  ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH internal constant want = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant investmentToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICurveFi internal constant StableSwapSTETH = ICurveFi(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);


    //AAVE Flashloan protection
    //bool internal awaitingFlash = false;

    //uint256 public maxSingleTrade;


    //DYDX Flashloan
    address private constant SOLO = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    //AAVE Flashloan
    address private constant AAVE_LENDING = 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8;
    ILendingPoolAddressesProvider public constant AAVEaddressesProvider = ILendingPoolAddressesProvider(AAVE_LENDING);
    // @notice emitted when trying to do Flash Loan. flashLoan address is 0x00 when no flash loan used
    event Leverage(uint256 amountRequested, uint256 amountGiven, bool usedydx, address flashLoan);
    

    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // Do not attempt to mint DAI if there are less than MIN_MINTABLE available
    uint256 internal constant MIN_MINTABLE = 500000 * WAD;

    // Maker vaults manager
    ManagerLike internal constant manager =
        ManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);

    // Token Adapter Module for collateral
    DaiJoinLike internal constant daiJoin =
        DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);

    // Liaison between oracles and core Maker contracts
    SpotLike internal constant spotter =
        SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);

    // Part of the Maker Rates Module in charge of accumulating stability fees
    JugLike internal constant jug =
        JugLike(0x19c0976f590D67707E62397C87829d896Dc0f1F1);

    // Debt Ceiling Instant Access Module
    DssAutoLine internal constant autoLine =
        DssAutoLine(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);

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
    // Adapted from https://github.com/makerdao/dss-proxy-actions/blob/master/src/DssProxyActions.sol#L639
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
    // Adapted from https://github.com/makerdao/dss-proxy-actions/blob/master/src/DssProxyActions.sol#L758
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
    // https://github.com/makerdao/dss/blob/master/src/spot.sol#L45
    function getLiquidationRatio(bytes32 ilk) public view returns (uint256) {
        (, uint256 liquidationRatio) = spotter.ilks(ilk);
        return liquidationRatio;
    }


    function getYieldBearingOSMPrice(bytes32 _ilk_yieldBearing, address _yieldBearingToUSDOSMProxyAddress) public view returns (uint256) {
        IOSMedianizer yieldBearingToUSDOSMProxy = IOSMedianizer(_yieldBearingToUSDOSMProxyAddress);
        // Use price from spotter as base
        uint256 minPrice = getSpotPrice(_ilk_yieldBearing);
        // Peek the OSM to get current price
        if (_yieldBearingToUSDOSMProxyAddress != address(0)) {
            try yieldBearingToUSDOSMProxy.read() returns (
                uint256 current,
                bool currentIsValid
            ) {
                if (currentIsValid && current > 0) {
                    minPrice = Math.min(minPrice, current);
                    //TEST: REMOVE BELOW AFTER TEST
                    //minPrice = current;
                }
            } catch {
                // Ignore price peek()'d from OSM. Maybe we are no longer authorized.
            }

            // Peep the OSM to get future price
            try yieldBearingToUSDOSMProxy.foresight() returns (
                uint256 future,
                bool futureIsValid
            ) {
                if (futureIsValid && future > 0) {
                    minPrice = Math.min(minPrice, future);
                    //TEST: REMOVE BELOW AFTER TEST
                    //minPrice = future;
                }
            } catch {
                // Ignore price peep()'d from OSM. Maybe we are no longer authorized.
            }
        }
        return minPrice;
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

        uint256 totalCollateralValue =
            balanceOfCdp(cdpId, ilk).mul(price).div(WAD);
        uint256 totalDebt = debtForCdp(cdpId, ilk);

        // If for some reason we do not have debt (e.g: deposits under dust)
        // make sure the operation does not revert
        if (totalDebt == 0) {
            totalDebt = 1;
        }

        return
            totalCollateralValue.mul(collateralizationRatioPrecision).div(
                totalDebt
            );
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
        VatLike vat = VatLike(manager.vat());
        (uint256 Art, uint256 rate, , uint256 line, ) = vat.ilks(ilk);

        // Total debt in [rad] (wad * ray)
        uint256 vatDebt = Art.mul(rate);

        if (vatDebt >= line || line.sub(vatDebt).div(RAY) < MIN_MINTABLE) {
            return false;
        }

        return true;
    }

    // ----------------- INTERNAL FUNCTIONS -----------------

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

    // Adapted from https://github.com/makerdao/dss-proxy-actions/blob/master/src/DssProxyActions.sol#L161
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

    // Adapted from https://github.com/makerdao/dss-proxy-actions/blob/master/src/DssProxyActions.sol#L183
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


    //AAVE FLASHLOAN:
    function initiateFlashLoan(uint256 _totalRepayAmount, uint256 cdpIdFlash) public {

        emit DebugDelegate(1234, _totalRepayAmount);
        emit DebugDelegate(11108, balanceOfInvestmentToken());
        bool usedydx = true;
        //IERC20 token = IERC20(_token);
        IERC20 token = investmentToken;
        address _token = address(investmentToken);
        uint256 currentDebt = debtForCdp(cdpIdFlash, ilk_yieldBearing).add(1);
        uint256 payWithFlashloan = _totalRepayAmount - Math.min(balanceOfInvestmentToken(), _totalRepayAmount);
        emit DebugDelegate(11109, payWithFlashloan);
        //If entire debt can be paid off with investment tokens in wallet
        if (currentDebt == _totalRepayAmount && payWithFlashloan == 0) {
            _checkAllowance(daiJoinAddress(), _token, currentDebt);
            wipeAndFreeGem(gemJoinFlash, cdpIdFlash, balanceOfCdp(cdpIdFlash, ilk_yieldBearing), currentDebt);
            return;
        }

        if (payWithFlashloan < 1e17) {
            // if above 0, but below 0.1 DAI, set minimum to 0.1 DAI 
            payWithFlashloan = 1e17;
        }
        

        //---------------------------
        //DYDX or AAVE
        //--------------------------
        ILendingPool AAVElendingPool = ILendingPool(AAVEaddressesProvider.getLendingPool());
        //uint256 availableAAVELiquidity = token.balanceOf(address(0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3)).sub(1);
        uint256 availableAAVELiquidity = token.balanceOf(address(AAVElendingPool));
        emit DebugDelegate(11110, payWithFlashloan);
        emit DebugDelegate(11111, availableAAVELiquidity);
        uint256 amountInSolo = token.balanceOf(SOLO);
        emit DebugDelegate(11112, amountInSolo);
        if ( (amountInSolo >= payWithFlashloan || amountInSolo >= availableAAVELiquidity) && token.balanceOf(address(this)) >= 1000 ) {
        // DYDX
            usedydx = true;
            //emit DebugDelegate(11113, payWithFlashloan);
            ISoloMargin solo = ISoloMargin(SOLO);
            //emit DebugDelegate(11113, payWithFlashloan);
            uint256 numMarkets = solo.getNumMarkets();
            emit DebugDelegate(11113, numMarkets);
            address curToken;
            //dyDxMarketID for DAI is 3. Use loop below to find off-chain.
            uint256 dyDxMarketId = 3;
            /*
            for (uint256 i = 0; i < numMarkets; i++) {
                emit DebugDelegate(11113, i);
                curToken = solo.getMarketTokenAddress(i);
                if (curToken == _token) {
                    dyDxMarketId = i;
                    return;
                }
            }
            */
            emit DebugDelegate(11113, payWithFlashloan);
            _checkAllowance(address(SOLO), _token, payWithFlashloan);
            payWithFlashloan = Math.min(amountInSolo, payWithFlashloan);
            emit DebugDelegate(11114, payWithFlashloan);
            //payWithFlashloan = payWithFlashloan.add(2); // we need to overcollateralise on way back
            bytes memory data = abi.encode(usedydx, payWithFlashloan, payWithFlashloan.add(2));

            // 1. Withdraw $
            // 2. Call callFunction(...)
            // 3. Deposit back $
            Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

            operations[0] = _getWithdrawAction(dyDxMarketId, payWithFlashloan);
            operations[1] = _getCallAction(
                // Encode custom data for callFunction
                data
            );
            operations[2] = _getDepositAction(dyDxMarketId, payWithFlashloan.add(2));

            Account.Info[] memory accountInfos = new Account.Info[](1);
            accountInfos[0] = _getAccountInfo();

            solo.operate(accountInfos, operations);
            emit DebugDelegate(11115, payWithFlashloan);

            //emit Leverage(payWithFlashloan, payWithFlashloan, usedydx, SOLO);
        
        } else {
            //AAVE FLASHLOAN:
            usedydx = false;
            payWithFlashloan = Math.min(availableAAVELiquidity, payWithFlashloan);

            bytes memory data = abi.encode(usedydx, payWithFlashloan);

            //anyone can call aave flash loan to us. (for some reason. grrr)
            //awaitingFlash = true;
            emit DebugDelegate(22222, payWithFlashloan);
            AAVElendingPool.flashLoan(address(this), _token, payWithFlashloan.add(1), data);

            //awaitingFlash = false;

            //emit Leverage(payWithFlashloan, payWithFlashloan.add(1), usedydx, AAVE_LENDING);
        }

    }

    //Aave calls this function after doing flash loan
    function executeFlashloan(
        bool usedydx,
        uint256 _flashloanAmount,
        uint256 _fee,
        //bytes calldata _params,
        uint256 cdpIdFlash,
        ISwap router,
        uint256 _totalRepayAmount
    ) external {
        if (_flashloanAmount == 0) {
            return;
        }
        //(bool usedydx, uint256 amount) = abi.decode(_params, (bool, uint256));
        //require(msg.sender == addressesProvider.getLendingPool(), "NOT_AAVE");
        //require(awaitingFlash, "Malicious"); 
        address investmentTokenAdd = address(investmentToken);
        address wantAdd = address(want);
        address yieldBearingAdd = address(yieldBearing);

        //calculate how much is _totalRepayAmount
        emit DebugDelegate(40, _totalRepayAmount);
        emit DebugDelegate(41, _flashloanAmount);
        //Paying back AAVE needs to be +fee
        uint256 repayAmount = _flashloanAmount.add(_fee);
        //How much yieldBearing it takes to buy enough investmentToken through curve 
        uint256 curveroute =             
            yieldBearing.getWstETHByStETH(
                StableSwapSTETH.get_dy(0, 1, 
                router.getAmountsIn(repayAmount, 
                    getTokenOutPath(wantAdd, investmentTokenAdd))[0]
                ));

        //Account for slippage through the curve route
        //uint256 slippageProtection = address(this).slippageProtection;
        uint256 slippageProtection = 100;
        curveroute = curveroute.mul(10000 + slippageProtection).div(10000).add(1);
        //How much yieldBearing it takes to buy enough investmentToken through router
        uint256 routerroute;
        
        try router.getAmountsIn(repayAmount, getTokenOutPath(yieldBearingAdd, investmentTokenAdd)) returns (uint256[] memory result) {
            routerroute = result[0].add(1);
        } catch {
            routerroute = curveroute + 1e18;
        }

        emit DebugDelegate(95, curveroute);
        emit DebugDelegate(96, routerroute);
        uint256 repayAmountInYieldBearing = Math.min(curveroute, routerroute);
        //uint256 repayAmountInYieldBearing = curveroute;
        //uint256 repayAmountInYieldBearing = routerroute;
        emit DebugDelegate(97, repayAmountInYieldBearing);
        
        //DEBT WITHDRAWAL:
        uint256 currentDebt = debtForCdp(cdpIdFlash, ilk_yieldBearing).add(1);
        emit DebugDelegate(42, currentDebt);
        //_totalRepayAmount not more than current total debt, collateral withdrawal not more than total collateral
        _totalRepayAmount = Math.min(_totalRepayAmount, currentDebt);
        repayAmountInYieldBearing = Math.min(repayAmountInYieldBearing, balanceOfCdp(cdpIdFlash, ilk_yieldBearing));

        //if the remaining debt is below the debtFloor & retainDebtFloor == false --> pay off full debt
        //if the remaining debt is below the debtFloor & retainDebtFloor == true --> pay off only until debtFloor+1e
        //debtFloor.add(1e15)
        //30k debt - 30k repay = 0 < debtFloor --> total repay = full debt = 15k1
        //30k debt - 20k repay = 10k < debtFloor --> total repay = full debt = 15k1
        //30k debt - 15k repay = 15k < debtFloor --> total repay = full debt = 15k1
        if ( (currentDebt - _totalRepayAmount) <= debtFloor(ilk_yieldBearing).add(1e15)){
            _totalRepayAmount = currentDebt;
            emit DebugDelegate(666, _totalRepayAmount);
        }
        //if full debt is repaid: unlock collateral
        if (_totalRepayAmount == currentDebt){
            repayAmountInYieldBearing = balanceOfCdp(cdpIdFlash, ilk_yieldBearing);
        }

        _checkAllowance(daiJoinAddress(), investmentTokenAdd, currentDebt);
        emit DebugDelegate(98, repayAmountInYieldBearing);
        emit DebugDelegate(99, balanceOfCdp(cdpIdFlash, ilk_yieldBearing));
        emit DebugDelegate(100, _totalRepayAmount);
        emit DebugDelegate(101, balanceOfInvestmentToken());
        //emit DebugDelegate(101, IERC20(_reserve).balanceOf(address(this)));
        _totalRepayAmount = Math.min(_totalRepayAmount, balanceOfInvestmentToken());
        wipeAndFreeGem(gemJoinFlash, cdpIdFlash, repayAmountInYieldBearing, _totalRepayAmount);        
        //--- MAKER DEBT REPAID & YIELD BEARING UNLOCKED!

        //--- SWAPS FOR FLASHLOAN REPAYMENT
        //Swap yield bearing OR want for investment token
        //Curve or router route?
        if (curveroute < routerroute){
        //if (1 == 1){
            //swap yieldBearingAmount 
            emit DebugDelegate(199, repayAmount);
            emit DebugDelegate(200, repayAmountInYieldBearing);
            emit DebugDelegate(201, curveroute);
            emit DebugDelegate(202, balanceOfYieldBearing());
            emit DebugDelegate(203, want.balanceOf(address(this)));
            _swapYieldBearingToWant(curveroute, 50); //100 = 1%
            emit DebugDelegate(204, balanceOfYieldBearing());
            emit DebugDelegate(205, want.balanceOf(address(this)));
            //Let router swap want instead of yieldBearing to investmentToken
            yieldBearingAdd = wantAdd;
        }
        _checkAllowance(address(router), yieldBearingAdd, repayAmount);
        //Swap either yieldBearing (or want) to investmentToken to repay flashloan debt outstanding to AAVE
        router.swapTokensForExactTokens(
            repayAmount,
            type(uint256).max,
            getTokenOutPath(yieldBearingAdd, investmentTokenAdd),
            address(this),
            now
        );
        emit DebugDelegate(206, balanceOfInvestmentToken());
        emit DebugDelegate(207, want.balanceOf(address(this)));
        //PAYBACK: DYDX

        if (usedydx == false) {
            //Pay back AAVE+fee:
            address core = AAVEaddressesProvider.getLendingPoolCore();
            _checkAllowance(core, investmentTokenAdd, repayAmount);
            investmentToken.safeTransfer(core, repayAmount); 
        }       
    }

    function getTokenOutPath(address _token_in, address _token_out)
        public
        pure
        returns (address[] memory _path)
    {
        _path = new address[](2);
        _path[0] = _token_in;
        _path[1] = _token_out;
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) public {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            //IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, type(uint256).max);
        }
    }

    function _swapInvestmentTokenToWant(uint256 _amount, ISwap _router) external returns (uint256) {
        if (_amount < 1000) {
            return 0;
        }
        _checkAllowance(address(_router), address(investmentToken), _amount);
        return _router.swapExactTokensForTokens(
            _amount,
            0,
            getTokenOutPath(address(investmentToken), address(want)),
            address(this),
            now
        )[1];
        //the [1] value of the array is the out value of the out token (want) of the swap
    }

    function _swapWantToYieldBearing(uint256 _amount, address _referal) external returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        //---WETH (ethwrapping withdraw) --> ETH --- Unwrap WETH to ETH (to be used in Curve)
        want.withdraw(_amount);  
        _amount = address(this).balance;
        DebugDelegate(666, _amount);              
        //---ETH (steth.submit OR stableswap01) --> STETH --- test if mint or buy
        DebugDelegate(667, StableSwapSTETH.get_dy(0,1,_amount));
        if (StableSwapSTETH.get_dy(0, 1, _amount) < _amount){
            //LIDO stETH MINT: 
            stETH.submit{value: _amount}(_referal);
        }else{ 
            //approve Curve ETH/stETH StableSwap & exchange eth to steth
            _checkAllowance(address(StableSwapSTETH), address(stETH), _amount);       
            StableSwapSTETH.exchange{value: _amount}(0, 1, _amount, _amount);
        }
        //---STETH (wsteth wrap) --> WSTETH
        DebugDelegate(668, balanceOfstETH());
        _checkAllowance(address(yieldBearing), address(stETH), balanceOfstETH());
        yieldBearing.wrap(balanceOfstETH());
        DebugDelegate(669, balanceOfYieldBearing());
        //---> all WETH now to WSTETH
        return balanceOfYieldBearing();
    }

    function _swapYieldBearingToWant(uint256 _amount, uint256 _slippageProtection) public {
        if (_amount == 0) {
            return;
        }
        //--WSTETH --> STETH
        //emit Debug(6969, balanceOfYieldBearing());
        _amount = Math.min(_amount, balanceOfYieldBearing());
        _amount = yieldBearing.unwrap(_amount);
        //emit Debug(69, _amount);
        //emit Debug(111, StableSwapSTETH.get_dy(1, 0, _amount));  
        //---STEHT --> ETH
        _checkAllowance(address(StableSwapSTETH), address(stETH), _amount);
        StableSwapSTETH.exchange(1, 0, _amount, _amount.mul(10000 - _slippageProtection).div(10000));
        //Re-Wrap it back up: ETH to WETH
        want.deposit{value: address(this).balance}();
    }
/*
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
*/
    function balanceOfYieldBearing() public view returns (uint256) {
        return yieldBearing.balanceOf(address(this));
    }

    function balanceOfstETH() public view returns (uint256) {
        return stETH.balanceOf(address(this));
    }

    function balanceOfInvestmentToken() public view returns (uint256) {
        uint256 tokenBalance = investmentToken.balanceOf(address(this));
        if (tokenBalance > 1000) {
            tokenBalance = tokenBalance.sub(1000);
        } else {
            tokenBalance = 0;
        }
        return tokenBalance;
    }



    //DYDX FlashLoanBase:
    function _getAccountInfo() internal view returns (Account.Info memory) {
        return Account.Info({owner: address(this), number: 1});
    }

    function _getWithdrawAction(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return
            Actions.ActionArgs({
                actionType: Actions.ActionType.Withdraw,
                accountId: 0,
                amount: Types.AssetAmount({
                    sign: false,
                    denomination: Types.AssetDenomination.Wei,
                    ref: Types.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: ""
            });
    }

    function _getCallAction(bytes memory data) internal view returns (Actions.ActionArgs memory) {
        return
            Actions.ActionArgs({
                actionType: Actions.ActionType.Call,
                accountId: 0,
                amount: Types.AssetAmount({sign: false, denomination: Types.AssetDenomination.Wei, ref: Types.AssetReference.Delta, value: 0}),
                primaryMarketId: 0,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: data
            });
    }

    function _getDepositAction(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return
            Actions.ActionArgs({
                actionType: Actions.ActionType.Deposit,
                accountId: 0,
                amount: Types.AssetAmount({
                    sign: true,
                    denomination: Types.AssetDenomination.Wei,
                    ref: Types.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: ""
            });
    }















}
