// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/math/Math.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./libraries/MakerDaiDelegateLib.sol";

import "../interfaces/chainlink/AggregatorInterface.sol";
import "../interfaces/swap/ISwap.sol";
import "../interfaces/yearn/IBaseFee.sol";
import "../interfaces/yearn/IOSMedianizer.sol";
import "../interfaces/yearn/IVault.sol";

import "../interfaces/curve/Curve.sol";
import "../interfaces/lido/ISteth.sol";
import "../interfaces/lido/IWstETH.sol";
import "../interfaces/UniswapInterfaces/IWETH.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //event DebugTokenHeldByStrategy(string _string, uint _value);
    //Hardcoded Options: YieldBearing, Referal:
    IWstETH public constant yieldBearing =  IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    //IERC20 internal yieldBearing = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);  //WETH for test
    uint256 yieldBearingPremiumPer10k = 10484;
    //Referal 
    address private referal = 0x35a83D4C1305451E0448fbCa96cAb29A7cCD0811;
    //SlippageProtection
    uint256 public slippageProtectionOut = 100;// = 50; //out of 10000. 50 = 0.5%

    //----------- Lido & Curve & DAI INIT
    ISteth public constant stETH =  ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    //Curve ETH/stETH StableSwap
    ICurveFi public constant StableSwapSTETH = ICurveFi(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);


    //investmentToken = token to be borrowed and further invested
    // DAI
    IERC20 internal constant investmentToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    //ETH to WETH Contract: 1) deposit: wrap ETH --> WETH, 2) withdraw: unwrap WETH --> ETH  
    IWETH public constant ethwrapping = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  
    //----------- MAKER INIT    
    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // 100%
    uint256 internal constant MAX_BPS = WAD;

    // Maximum loss on withdrawal from yVault
    uint256 internal constant MAX_LOSS_BPS = 10000;

    // Wrapped Ether - Used for swaps routing
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // SushiSwap router
    ISwap internal constant sushiswapRouter =
        ISwap(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // Uniswap router
    ISwap internal constant uniswapRouter =
        ISwap(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Provider to read current block's base fee
    IBaseFee internal constant baseFeeProvider =
        IBaseFee(0xf8d0Ec04e94296773cE20eFbeeA82e76220cD549);

    // Token Adapter Module for collateral
    address public gemJoinAdapter;

    // Maker Oracle Security Module
    IOSMedianizer public wantToUSDOSMProxy;
    IOSMedianizer public yieldBearingToUSDOSMProxy;

    // Use Chainlink oracle to obtain latest want/ETH price
    AggregatorInterface public chainlinkWantToETHPriceFeed;

    // DAI yVault
    IVault public yVault;

    // Router used for swaps
    ISwap public router;

    // Collateral type of want
    bytes32 public ilk_want;

    // Collateral type of MAKER deposited collateral
    bytes32 public ilk_yieldBearing;

    // Our vault identifier
    uint256 public cdpId;

    // Our desired collaterization ratio
    uint256 public collateralizationRatio;

    // Allow the collateralization ratio to drift a bit in order to avoid cycles
    uint256 public rebalanceTolerance;

    // Max acceptable base fee to take more debt or harvest
    uint256 public maxAcceptableBaseFee;

    // Maximum acceptable loss on withdrawal. Default to 0.01%.
    uint256 public maxLoss;

    // If set to true the strategy will never try to repay debt by selling want
    bool public leaveDebtBehind;

    // Name of the strategy
    string internal strategyName;

    // ----------------- INIT FUNCTIONS TO SUPPORT CLONING -----------------

    constructor(
        address _vault,
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk_want,
        bytes32 _ilk_yieldBearing,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _yieldBearingToUSDOSMProxy,
        address _chainlinkWantToETHPriceFeed
    ) public BaseStrategy(_vault) {
        _initializeThis(
            _yVault,
            _strategyName,
            _ilk_want,
            _ilk_yieldBearing,
            _gemJoin,
            _wantToUSDOSMProxy,
            _yieldBearingToUSDOSMProxy,
            _chainlinkWantToETHPriceFeed
        );
    }

    function initialize(
        address _vault,
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk_want,
        bytes32 _ilk_yieldBearing,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _yieldBearingToUSDOSMProxy,
        address _chainlinkWantToETHPriceFeed
    ) public {
        // Make sure we only initialize one time
        require(address(yVault) == address(0)); // dev: strategy already initialized

        address sender = msg.sender;

        // Initialize BaseStrategy
        _initialize(_vault, sender, sender, sender);

        // Initialize cloned instance
        _initializeThis(
            _yVault,
            _strategyName,
            _ilk_want,
            _ilk_yieldBearing,
            _gemJoin,
            _wantToUSDOSMProxy,
            _yieldBearingToUSDOSMProxy,
            _chainlinkWantToETHPriceFeed
        );
    }

    function _initializeThis(
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk_want,
        bytes32 _ilk_yieldBearing,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _yieldBearingToUSDOSMProxy,
        address _chainlinkWantToETHPriceFeed
    ) internal {
        yVault = IVault(_yVault);
        strategyName = _strategyName;
        //yieldBearing = IERC20(_yieldBearingAddr);
        ilk_want = _ilk_want;
        ilk_yieldBearing = _ilk_yieldBearing;
        gemJoinAdapter = _gemJoin;
        wantToUSDOSMProxy = IOSMedianizer(_wantToUSDOSMProxy);
        yieldBearingToUSDOSMProxy = IOSMedianizer(_yieldBearingToUSDOSMProxy);
        chainlinkWantToETHPriceFeed = AggregatorInterface(
            _chainlinkWantToETHPriceFeed
        );

        // Set default router to SushiSwap
        router = sushiswapRouter;

        // Set health check to health.ychad.eth
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;

        cdpId = MakerDaiDelegateLib.openCdp(ilk_yieldBearing);
        require(cdpId > 0); // dev: error opening cdp

        // Current ratio can drift (collateralizationRatio -f rebalanceTolerance, collateralizationRatio + rebalanceTolerance)
        // Allow additional 15% in any direction (210, 240) by default
        rebalanceTolerance = (15 * MAX_BPS) / 100;

        // Minimum collaterization ratio on YFI-A is 175%
        // Use 225% as target
        collateralizationRatio = (225 * MAX_BPS) / 100;

        // If we lose money in yvDAI then we are not OK selling want to repay it
        leaveDebtBehind = true;

        // Define maximum acceptable loss on withdrawal to be 0.01%.
        maxLoss = 1;

        // Set max acceptable base fee to take on more debt to 60 gwei
        maxAcceptableBaseFee = 60 * 1e9;
    }

    //we get eth
    receive() external payable {}

    // ----------------- SETTERS & MIGRATION -----------------
/*
    // Maximum acceptable base fee of current block to take on more debt
    function setMaxAcceptableBaseFee(uint256 _maxAcceptableBaseFee)
        external
        onlyEmergencyAuthorized
    {
        maxAcceptableBaseFee = _maxAcceptableBaseFee;
    }
*/
    // Target collateralization ratio to maintain within bounds
    function setCollateralizationRatio(uint256 _collateralizationRatio)
        external
        onlyEmergencyAuthorized
    {
        require(
            _collateralizationRatio.sub(rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(MAX_BPS).div(
                    RAY
                )
        ); // dev: desired collateralization ratio is too low
        collateralizationRatio = _collateralizationRatio;
    }
/*
    // Rebalancing bands (collat ratio - tolerance, collat_ratio + tolerance)
    function setRebalanceTolerance(uint256 _rebalanceTolerance)
        external
        onlyEmergencyAuthorized
    {
        require(
            collateralizationRatio.sub(_rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(MAX_BPS).div(
                    RAY
                )
        ); // dev: desired rebalance tolerance makes allowed ratio too low
        rebalanceTolerance = _rebalanceTolerance;
    }

    // Max slippage to accept when withdrawing from yVault
    function setMaxLoss(uint256 _maxLoss) external onlyVaultManagers {
        require(_maxLoss <= MAX_LOSS_BPS); // dev: invalid value for max loss
        maxLoss = _maxLoss;
    }

    // If set to true the strategy will never sell want to repay debts
    function setLeaveDebtBehind(bool _leaveDebtBehind)
        external
        onlyEmergencyAuthorized
    {
        leaveDebtBehind = _leaveDebtBehind;
    }
 //SIZE OPTIMISATION 
    // Required to move funds to a new cdp and use a different cdpId after migration
    // Should only be called by governance as it will move funds
    function shiftToCdp(uint256 newCdpId) external onlyGovernance {
        MakerDaiDelegateLib.shiftCdp(cdpId, newCdpId);
        cdpId = newCdpId;
    }

    // Move yvDAI funds to a new yVault
    function migrateToNewDaiYVault(IVault newYVault) external onlyGovernance {
        uint256 balanceOfYVault = yVault.balanceOf(address(this));
        if (balanceOfYVault > 0) {
            yVault.withdraw(balanceOfYVault, address(this), maxLoss);
        }
        investmentToken.safeApprove(address(yVault), 0);
        yVault = newYVault;
        _depositInvestmentTokenInYVault();
    }

    // Allow address to manage Maker's CDP
    function grantCdpManagingRightsToUser(address user, bool allow)
        external
        onlyGovernance
    {
        MakerDaiDelegateLib.allowManagingCdp(cdpId, user, allow);
    }

    // Allow switching between Uniswap and SushiSwap
    function switchDex(bool isUniswap) external onlyVaultManagers {
        if (isUniswap) {
            router = uniswapRouter;
        } else {
            router = sushiswapRouter;
        }
    }

    // Allow external debt repayment
    // Attempt to take currentRatio to target c-ratio
    // Passing zero will repay all debt if possible
    function emergencyDebtRepayment(uint256 currentRatio)
        external
        onlyVaultManagers
    {
        _repayDebt(currentRatio);
    }

    // Allow repayment of an arbitrary amount of Dai without having to
    // grant access to the CDP in case of an emergency
    // Difference with `emergencyDebtRepayment` function above is that here we
    // are short-circuiting all strategy logic and repaying Dai at once
    // This could be helpful if for example yvDAI withdrawals are failing and
    // we want to do a Dai airdrop and direct debt repayment instead
    function repayDebtWithDaiBalance(uint256 amount)
        external
        onlyVaultManagers
    {
        _repayInvestmentTokenDebt(amount);
    }
*/
    // ******** OVERRIDEN METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return strategyName;
    }

    function delegatedAssets() external view override returns (uint256) {
        return _convertInvestmentTokenAmountToWant(_valueOfInvestment());
    }

    function estimatedTotalAssets() public view override returns (uint256) {  //measured in WANT
        return
            balanceOfWant()   //free WANT balance in wallet
                .add(ethToWant(address(this).balance))  //free ETH balance in wallet
                //.add(stETH.balanceOf(address(this))) //free stETH
                .add(_convertYieldBearingAmountToWant(yieldBearing.balanceOf(address(this)))) // There should not be any free yieldBearing in wallet
                .add(_convertYieldBearingAmountToWant(balanceOfMakerVault()))   //Collateral on Maker --> yieldBearing --> WANT 
                .add(_convertInvestmentTokenAmountToWant(balanceOfInvestmentToken()))  // free DAI balance in wallet --> WANT
                .add(_convertInvestmentTokenAmountToWant(_valueOfInvestment()))  //locked yvDAI shares --> DAI --> WANT
                .sub(_convertInvestmentTokenAmountToWant(balanceOfDebt()));  //DAI debt of maker --> WANT
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;

        // Claim rewards from yVault
        _takeYVaultProfit();

        uint256 totalAssetsAfterProfit = estimatedTotalAssets();

        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        uint256 _amountFreed;
        (_amountFreed, _loss) = liquidatePosition(
            _debtOutstanding.add(_profit)
        );
        _debtPayment = Math.min(_debtOutstanding, _amountFreed);

        if (_loss > _profit) {
            // Example:
            // debtOutstanding 100, profit 50, _amountFreed 100, _loss 50
            // loss should be 0, (50-50)
            // profit should endup in 0
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            // Example:
            // debtOutstanding 100, profit 50, _amountFreed 140, _loss 10
            // _profit should be 40, (50 profit - 10 loss)
            // loss should end up in be 0
            _profit = _profit.sub(_loss);
            _loss = 0;
        }
    }


    function adjustPosition(uint256 _debtOutstanding) internal override {
        // Update accumulated stability fees,  Update the debt ceiling using DSS Auto Line
        MakerDaiDelegateLib.keepBasicMakerHygiene(ilk_yieldBearing);
        // If we have enough want to convert and deposit more into the maker vault, we do it
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debtOutstanding) {
            //Determine amount of Want to Deposit
            _depositToMakerVault(wantBalance.sub(_debtOutstanding));
        }

        // Allow the ratio to move a bit in either direction to avoid cycles
        uint256 currentRatio = getCurrentMakerVaultRatio();
        if (currentRatio < collateralizationRatio.sub(rebalanceTolerance)) {
            _repayDebt(currentRatio);
        } else if (
            currentRatio > collateralizationRatio.add(rebalanceTolerance)
        ) {
            _mintMoreInvestmentToken();
        }

        // If we have anything left to invest then deposit into the yVault
        _depositInvestmentTokenInYVault();
    }

    function liquidatePosition(uint256 _wantAmountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        //exchange free intermediaries and free yieldbearing to want
        _cleanUpToWant();

        uint256 collateralPrice = _getYieldBearingUSDPrice();
        uint256 collateralBalance = balanceOfMakerVault();
        uint256 wantBalance = balanceOfWant();
        // Check if we can handle it without freeing collateral
        if (wantBalance >= _wantAmountNeeded) {
            return (_wantAmountNeeded, 0);
        }
        // We only need to free the amount of want not readily available by unlocking collateral
        uint256 yieldBearingAmountToFree = _convertWantAmountToYieldBearing(_wantAmountNeeded.sub(wantBalance)); 
        // We cannot free more than what we have locked
        yieldBearingAmountToFree = Math.min(yieldBearingAmountToFree, collateralBalance);
        //Total Debt in InvestmentToken
        uint256 totalDebt = balanceOfDebt();
        // If for some reason we do not have debt, make sure the operation does not revert
        if (totalDebt == 0) {
            totalDebt = 1;
        }

        //New Ratio through calculation with terms denominated in investment token
        uint256 yieldBearingAmountToFreeIT = yieldBearingAmountToFree.mul(collateralPrice).div(WAD);
        uint256 collateralIT = collateralBalance.mul(collateralPrice).div(WAD);
        uint256 newRatio =
            collateralIT.sub(yieldBearingAmountToFreeIT).mul(MAX_BPS).div(totalDebt);

        // Attempt to repay necessary debt to restore the target collateralization ratio
        _repayDebt(newRatio);

        // Unlock as much collateral as possible while keeping the target ratio
        yieldBearingAmountToFree = Math.min(yieldBearingAmountToFree, _maxWithdrawal());
        //emit DebugTokenHeldByStrategy("liqpos: before _freeColl&repayDai - balanceOfMakervault",balanceOfMakerVault());
        //emit DebugTokenHeldByStrategy("liqpos: before _freeColl&repayDai - wantbalance",want.balanceOf(address(this)));
        //emit DebugTokenHeldByStrategy("liqpos: before _freeColl&repayDai - yBbalance",yieldBearing.balanceOf(address(this)));
        _freeCollateralAndRepayDai(yieldBearingAmountToFree, 0);
        //emit DebugTokenHeldByStrategy("liqpos: after _freeColl&repayDai - balanceOfMakervault",balanceOfMakerVault());
        //emit DebugTokenHeldByStrategy("liqpos: after _freeColl&repayDai - wantbalance",want.balanceOf(address(this)));
        //emit DebugTokenHeldByStrategy("liqpos: after _freeColl&repayDai - yBbalance",yieldBearing.balanceOf(address(this)));
        _swapYieldBearingToWant(yieldBearingAmountToFree);
        //emit DebugTokenHeldByStrategy("liqpos: after _swap - wantbalance",want.balanceOf(address(this)));

        //Maximum amount of want from easy ways now free in strategy wallet 
        // If we still need more want to repay, we may need to unlock some collateral to sell
        if (
            !leaveDebtBehind &&
            balanceOfWant() < _wantAmountNeeded &&
            balanceOfDebt() > 0
        ) {
            _sellCollateralToRepayRemainingDebtIfNeeded();
            _swapYieldBearingToWant(yieldBearing.balanceOf(address(this)));
        }
        //loss calculation and returning lidated amount
        uint256 looseWant = balanceOfWant();
        if (_wantAmountNeeded > looseWant) {
            _liquidatedAmount = looseWant;
            _loss = _wantAmountNeeded.sub(looseWant);
        } else {
            _liquidatedAmount = _wantAmountNeeded;
            _loss = 0;
        }
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        (_amountFreed, ) = liquidatePosition(estimatedTotalAssets());
    }

    function harvestTrigger(uint256 callCost)
        public
        view
        override
        returns (bool)
    {
        return isCurrentBaseFeeAcceptable() && super.harvestTrigger(callCost);
    }

    function tendTrigger(uint256 callCostInWei)
        public
        view
        override
        returns (bool)
    {
        // Nothing to adjust if there is no collateral locked
        if (balanceOfMakerVault() == 0) {
            return false;
        }

        uint256 currentRatio = getCurrentMakerVaultRatio();

        // If we need to repay debt and are outside the tolerance bands,
        // we do it regardless of the call cost
        if (currentRatio < collateralizationRatio.sub(rebalanceTolerance)) {
            return true;
        }

        // Mint more DAI if possible
        return
            currentRatio > collateralizationRatio.add(rebalanceTolerance) &&
            balanceOfDebt() > 0 &&
            isCurrentBaseFeeAcceptable() &&
            MakerDaiDelegateLib.isDaiAvailableToMint(ilk_yieldBearing);
    }

    function prepareMigration(address _newStrategy) internal override {
        // Transfer Maker Vault ownership to the new startegy
        MakerDaiDelegateLib.transferCdp(cdpId, _newStrategy);

        // Move yvDAI balance to the new strategy
        IERC20(yVault).safeTransfer(
            _newStrategy,
            yVault.balanceOf(address(this))
        );
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        if (address(want) == address(WETH)) {
            return _amtInWei;
        }

        uint256 price = uint256(chainlinkWantToETHPriceFeed.latestAnswer());
        return _amtInWei.mul(WAD).div(price);
    }

    // ----------------- INTERNAL FUNCTIONS SUPPORT -----------------

    function _repayDebt(uint256 currentRatio) internal {
        uint256 currentDebt = balanceOfDebt();

        // Nothing to repay if we are over the collateralization ratio
        // or there is no debt
        if (currentRatio > collateralizationRatio || currentDebt == 0) {
            return;
        }

        // ratio = collateral / debt
        // collateral = current_ratio * current_debt
        // collateral amount is invariant here so we want to find new_debt
        // so that new_debt * desired_ratio = current_debt * current_ratio
        // new_debt = current_debt * current_ratio / desired_ratio
        // and the amount to repay is the difference between current_debt and new_debt
        uint256 newDebt =
            currentDebt.mul(currentRatio).div(collateralizationRatio);

        uint256 amountToRepay;

        // Maker will revert if the outstanding debt is less than a debt floor
        // called 'dust'. If we are there we need to either pay the debt in full
        // or leave at least 'dust' balance (10,000 DAI for YFI-A)
        uint256 debtFloor = MakerDaiDelegateLib.debtFloor(ilk_yieldBearing);
        if (newDebt <= debtFloor) {
            // If we sold want to repay debt we will have DAI readily available in the strategy
            // This means we need to count both yvDAI shares and current DAI balance
            uint256 totalInvestmentAvailableToRepay =
                _valueOfInvestment().add(balanceOfInvestmentToken());

            if (totalInvestmentAvailableToRepay >= currentDebt) {
                // Pay the entire debt if we have enough investment token
                amountToRepay = currentDebt;
            } else {
                // Pay just 0.1 cent above debtFloor (best effort without liquidating want)
                amountToRepay = currentDebt.sub(debtFloor).sub(1e15);
            }
        } else {
            // If we are not near the debt floor then just pay the exact amount
            // needed to obtain a healthy collateralization ratio
            amountToRepay = currentDebt.sub(newDebt);
        }

        uint256 balanceIT = balanceOfInvestmentToken();
        if (amountToRepay > balanceIT) {
            _withdrawFromYVault(amountToRepay.sub(balanceIT));
        }
        _repayInvestmentTokenDebt(amountToRepay);
    }

    function _sellCollateralToRepayRemainingDebtIfNeeded() internal {
        //DAI value of yvDAI owned by strategy
        uint256 currentInvestmentValue = _valueOfInvestment();
        //DAI Debt on MAKER   minus    DAI value of yvDAI owned by strategy
        uint256 investmentLeftToAcquire =
            balanceOfDebt().sub(currentInvestmentValue);

        uint256 investmentLeftToAcquireInWant =
            _convertInvestmentTokenAmountToWant(investmentLeftToAcquire);

        if (investmentLeftToAcquireInWant <= balanceOfWant()) {
            _buyInvestmentTokenWithWant(investmentLeftToAcquire);
            _repayDebt(0);
            _freeCollateralAndRepayDai(balanceOfMakerVault(), 0);
        }
    }

    // Mint the maximum DAI possible for the locked collateral
    function _mintMoreInvestmentToken() internal {
        uint256 price = _getYieldBearingUSDPrice();
        uint256 amount = balanceOfMakerVault();

        uint256 daiToMint =
            amount.mul(price).mul(MAX_BPS).div(collateralizationRatio).div(WAD);
        daiToMint = daiToMint.sub(balanceOfDebt());
        _lockCollateralAndMintDai(0, daiToMint);
    }

    function _withdrawFromYVault(uint256 _amountIT) internal returns (uint256) {
        if (_amountIT == 0) {
            return 0;
        }
        // No need to check allowance because the contract == token
        uint256 balancePrior = balanceOfInvestmentToken();
        uint256 sharesToWithdraw =
            Math.min(
                _investmentTokenToYShares(_amountIT),
                yVault.balanceOf(address(this))
            );
        if (sharesToWithdraw == 0) {
            return 0;
        }
        yVault.withdraw(sharesToWithdraw, address(this), maxLoss);
        return balanceOfInvestmentToken().sub(balancePrior);
    }

    function _depositInvestmentTokenInYVault() internal {
        uint256 balanceIT = balanceOfInvestmentToken();
        if (balanceIT > 0) {
            _checkAllowance(
                address(yVault),
                address(investmentToken),
                balanceIT
            );

            yVault.deposit();
        }
    }

    function _repayInvestmentTokenDebt(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 debt = balanceOfDebt();
        uint256 balanceIT = balanceOfInvestmentToken();

        // We cannot pay more than loose balance
        amount = Math.min(amount, balanceIT);

        // We cannot pay more than we owe
        amount = Math.min(amount, debt);

        _checkAllowance(
            MakerDaiDelegateLib.daiJoinAddress(),
            address(investmentToken),
            amount
        );

        if (amount > 0) {
            // When repaying the full debt it is very common to experience Vat/dust
            // reverts due to the debt being non-zero and less than the debt floor.
            // This can happen due to rounding when _wipeAndFreeGem() divides
            // the DAI amount by the accumulated stability fee rate.
            // To circumvent this issue we will add 1 Wei to the amount to be paid
            // if there is enough investment token balance (DAI) to do it.
            if (debt.sub(amount) == 0 && balanceIT.sub(amount) >= 1) {
                amount = amount.add(1);
            }

            // Repay debt amount without unlocking collateral
            _freeCollateralAndRepayDai(0, amount);
        }
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

    function _takeYVaultProfit() internal {
        uint256 _debt = balanceOfDebt();
        uint256 _valueInVault = _valueOfInvestment();
        if (_debt >= _valueInVault) {
            return;
        }

        uint256 profit = _valueInVault.sub(_debt);
        uint256 ySharesToWithdraw = _investmentTokenToYShares(profit);
        if (ySharesToWithdraw > 0) {
            yVault.withdraw(ySharesToWithdraw, address(this), maxLoss);
            _sellAForB(
                balanceOfInvestmentToken(),
                address(investmentToken),
                address(want)
            );
        }
    }

    function _swapWantToYieldBearing(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        //---WETH (ethwrapping withdraw) --> ETH --- Unwrap WETH to ETH (to be used in Curve)
        ethwrapping.withdraw(_amount);  
        _amount = address(this).balance;              
        //---ETH (steth.submit OR stableswap01) --> STETH --- test if mint or buy
        if(StableSwapSTETH.get_dy(0, 1, _amount) < _amount){
            //LIDO stETH MINT: 
            stETH.submit{value: _amount}(referal);
        }else{ 
            //approve Curve ETH/stETH StableSwap & exchange eth to steth
            _checkAllowance(address(StableSwapSTETH), address(stETH), _amount);       
            StableSwapSTETH.exchange{value: _amount}(0, 1, _amount, _amount);
        }
        //---STETH (wsteth wrap) --> WSTETH
        _checkAllowance(address(yieldBearing), address(stETH), stETH.balanceOf(address(this)));
        yieldBearing.wrap(stETH.balanceOf(address(this)));
        //---> all WETH now to WSTETH
        return yieldBearing.balanceOf(address(this));
    }

    function _swapYieldBearingToWant(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        //--WSTETH --> STETH
        _amount = yieldBearing.unwrap(_amount);
        //---STEHT --> ETH
        StableSwapSTETH.exchange(1, 0, _amount, _amount*(10000-slippageProtectionOut)/10000);
        //Re-Wrap it back up: ETH to WETH
        ethwrapping.deposit{value: address(this).balance}();
        return want.balanceOf(address(this));
    }

    function _cleanUpToWant() internal {
        //--WSTETH --> STETH
        if (yieldBearing.balanceOf(address(this)) != 0) {
            yieldBearing.unwrap(yieldBearing.balanceOf(address(this)));
        }
        //---STEHT --> ETH
        if (stETH.balanceOf(address(this)) != 0) {
        StableSwapSTETH.exchange(1, 0, stETH.balanceOf(address(this)), stETH.balanceOf(address(this))*(10000-slippageProtectionOut*5)/10000);
        }
        //Re-Wrap it back up: ETH to WETH
        if (address(this).balance != 0) {
            ethwrapping.deposit{value: address(this).balance}();
        }
    }

    function _depositToMakerVault(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        //Exchange Want to YieldBearing to later deposit
        _amount = _swapWantToYieldBearing(_amount);
        //Check Allowance to lock Collateral 
        _checkAllowance(gemJoinAdapter, address(yieldBearing), _amount);
        uint256 price = _getYieldBearingUSDPrice();
        uint256 daiToMint = _amount.mul(price).mul(MAX_BPS).div(collateralizationRatio).div(WAD);
        _lockCollateralAndMintDai(_amount, daiToMint);
    }

    // Returns maximum collateral to withdraw while maintaining the target collateralization ratio
    function _maxWithdrawal() internal view returns (uint256) {
        // Denominated in yieldBearing
        uint256 totalCollateral = balanceOfMakerVault();

        // Denominated in investment token
        uint256 totalDebt = balanceOfDebt();

        // If there is no debt to repay we can withdraw all the locked collateral
        if (totalDebt == 0) {
            return totalCollateral;
        }

        uint256 price = _getYieldBearingUSDPrice();

        // Min collateral in yieldBearing that needs to be locked with the outstanding debt
        // Allow going to the lower rebalancing band
        uint256 minCollateral =
            collateralizationRatio
                .sub(rebalanceTolerance)
                .mul(totalDebt)
                .mul(WAD)
                .div(price)
                .div(MAX_BPS);

        // If we are under collateralized then it is not safe for us to withdraw anything
        if (minCollateral > totalCollateral) {
            return 0;
        }

        return totalCollateral.sub(minCollateral);
    }

    // ----------------- PUBLIC BALANCES AND CALCS -----------------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfInvestmentToken() public view returns (uint256) {
        return investmentToken.balanceOf(address(this));
    }

    function balanceOfDebt() public view returns (uint256) {
        return MakerDaiDelegateLib.debtForCdp(cdpId, ilk_yieldBearing);
    }

    // Returns collateral balance in the vault
    function balanceOfMakerVault() public view returns (uint256) {
        return MakerDaiDelegateLib.balanceOfCdp(cdpId, ilk_yieldBearing);
    }

    // Effective collateralization ratio of the vault
    function getCurrentMakerVaultRatio() public view returns (uint256) {
        return
            MakerDaiDelegateLib.getPessimisticRatioOfCdpWithExternalPrice(
                cdpId,
                ilk_yieldBearing,
                _getYieldBearingUSDPrice(),
                MAX_BPS
            );
    }

    // Check if current block's base fee is under max allowed base fee
    function isCurrentBaseFeeAcceptable() public view returns (bool) {
        uint256 baseFee;
        try baseFeeProvider.basefee_global() returns (uint256 currentBaseFee) {
            baseFee = currentBaseFee;
        } catch {
            // Useful for testing until ganache supports london fork
            // Hard-code current base fee to 1000 gwei
            // This should also help keepers that run in a fork without
            // baseFee() to avoid reverting and potentially abandoning the job
            baseFee = 1000 * 1e9;
        }

        return baseFee <= maxAcceptableBaseFee;
    }

    // ----------------- INTERNAL CALCS -----------------

    // Returns the minimum price of Want available in DAI
    function _getWantUSDPrice() internal view returns (uint256) {
        // Use price from spotter as base
        uint256 minPrice = MakerDaiDelegateLib.getSpotPrice(ilk_want);

        // Peek the OSM to get current price
        try wantToUSDOSMProxy.read() returns (
            uint256 current,
            bool currentIsValid
        ) {
            if (currentIsValid && current > 0) {
                minPrice = Math.min(minPrice, current);
            }
        } catch {
            // Ignore price peek()'d from OSM. Maybe we are no longer authorized.
        }

        // Peep the OSM to get future price
        try wantToUSDOSMProxy.foresight() returns (
            uint256 future,
            bool futureIsValid
        ) {
            if (futureIsValid && future > 0) {
                minPrice = Math.min(minPrice, future);
            }
        } catch {
            // Ignore price peep()'d from OSM. Maybe we are no longer authorized.
        }

        // If price is set to 0 then we hope no liquidations are taking place
        // Emergency scenarios can be handled via manual debt repayment or by
        // granting governance access to the CDP
        require(minPrice > 0); // dev: invalid spot price

        // par is crucial to this calculation as it defines the relationship between DAI and
        // 1 unit of value in the price
        return minPrice.mul(RAY).div(MakerDaiDelegateLib.getDaiPar());
    }

    // Returns the minimum price of yieldBearing available in DAI
    function _getYieldBearingUSDPrice() internal view returns (uint256) {
        return _getWantUSDPrice().mul(yieldBearingPremiumPer10k).div(10000);
    }

/* //SIZE OPTIMISATION 
        // Returns the minimum price available
    function _getYieldBearingUSDPrice() internal view returns (uint256) {
        // Use price from spotter as base
        uint256 minPrice = MakerDaiDelegateLib.getSpotPrice(ilk_yieldBearing);

        // Peek the OSM to get current price
        try yieldBearingToUSDOSMProxy.read() returns (
            uint256 current,
            bool currentIsValid
        ) {
            if (currentIsValid && current > 0) {
                minPrice = Math.min(minPrice, current);
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
            }
        } catch {
            // Ignore price peep()'d from OSM. Maybe we are no longer authorized.
        }

        // If price is set to 0 then we hope no liquidations are taking place
        // Emergency scenarios can be handled via manual debt repayment or by
        // granting governance access to the CDP
        require(minPrice > 0); // dev: invalid spot price

        // par is crucial to this calculation as it defines the relationship between DAI and
        // 1 unit of value in the price
        return minPrice.mul(RAY).div(MakerDaiDelegateLib.getDaiPar());
    }
*/



//TEST FUNCTION
//    function t_getYieldBearingAddress() public view returns (address) {
//        return address(yieldBearing);
//    }

//    function t_isDaiAvailableToMint() public view returns (bool) {
//        return MakerDaiDelegateLib.isDaiAvailableToMint(ilk_yieldBearing);
//    }
    // Effective collateralization ratio of the vault: 2.25 at the start
//    function t_getCurrentMakerVaultRatio() public view returns (uint256) {
//        return getCurrentMakerVaultRatio();
//    }

//    function t_getLiquidationRatio() public view returns (uint256) {
//        MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(MAX_BPS).div(RAY);
//    }



/*    function MakerDaiDelegateLibgetDaiPar() public view returns (uint256) {
        return MakerDaiDelegateLib.getDaiPar();
    }
*/
/*    
    function t_getYieldBearingUSDPrice() public view returns (uint256) {
        return _getYieldBearingUSDPrice();
    }
    function t_getWantUSDPrice() public view returns (uint256) {
        return _getWantUSDPrice();
    }
*/
        




    function _valueOfInvestment() internal view returns (uint256) {
        return
            yVault.balanceOf(address(this)).mul(yVault.pricePerShare()).div(
                10**yVault.decimals()
            );
    }

    function _investmentTokenToYShares(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(10**yVault.decimals()).div(yVault.pricePerShare());
    }

    function _lockCollateralAndMintDai(
        uint256 collateralAmount,
        uint256 daiToMint
    ) internal {
        MakerDaiDelegateLib.lockGemAndDraw(
            gemJoinAdapter,
            cdpId,
            collateralAmount,
            daiToMint,
            balanceOfDebt()
        );
    }

    function _freeCollateralAndRepayDai(
        uint256 collateralAmount,
        uint256 daiToRepay
    ) internal {
        MakerDaiDelegateLib.wipeAndFreeGem(
            gemJoinAdapter,
            cdpId,
            collateralAmount,
            daiToRepay
        );
    }

    // ----------------- TOKEN CONVERSIONS -----------------

    function _convertInvestmentTokenAmountToWant(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(WAD).div(_getWantUSDPrice());
    }

    function _convertYieldBearingAmountToWant(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(_getYieldBearingUSDPrice()).div(_getWantUSDPrice());
    }

    function _convertWantAmountToYieldBearing(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(_getWantUSDPrice()).div(_getYieldBearingUSDPrice());
    }

    function _getTokenOutPath(address _token_in, address _token_out)
        internal
        pure
        returns (address[] memory _path)
    {
        bool is_weth =
            _token_in == address(WETH) || _token_out == address(WETH);
        _path = new address[](is_weth ? 2 : 3);
        _path[0] = _token_in;

        if (is_weth) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(WETH);
            _path[2] = _token_out;
        }
    }

    function _sellAForB(
        uint256 _amount,
        address tokenA,
        address tokenB
    ) internal {
        if (_amount == 0 || tokenA == tokenB) {
            return;
        }

        _checkAllowance(address(router), tokenA, _amount);
        router.swapExactTokensForTokens(
            _amount,
            0,
            _getTokenOutPath(tokenA, tokenB),
            address(this),
            now
        );
    }

    function _buyInvestmentTokenWithWant(uint256 _amount) internal {
        if (_amount == 0 || address(investmentToken) == address(want)) {
            return;
        }

        _checkAllowance(address(router), address(want), _amount);
        router.swapTokensForExactTokens(
            _amount,
            type(uint256).max,
            _getTokenOutPath(address(want), address(investmentToken)),
            address(this),
            now
        );
    }
}
