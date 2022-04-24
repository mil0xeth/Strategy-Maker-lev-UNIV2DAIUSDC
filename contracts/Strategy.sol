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

import "../interfaces/yearn/IBaseFee.sol";
import "../interfaces/yearn/IVault.sol";
//import "../interfaces/yearn/IOSMedianizer.sol";
//import "../interfaces/chainlink/AggregatorInterface.sol";

import "../interfaces/UniswapInterfaces/IWETH.sol";
import "../interfaces/lido/ISteth.sol";
import "../interfaces/lido/IWstETH.sol";
import "../interfaces/curve/Curve.sol";

//AMM Interface:
//import "../interfaces/swap/ISwapRouter.sol";
import "../interfaces/swap/ISwap.sol";


contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event Debug(uint256 _number, uint _value);

    //yieldBearing used as collateral in Maker. Here: WSTETH 
    IWstETH internal constant yieldBearing = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    // Collateral type of want. Here: WETH
    bytes32 internal ilk_want = 0x4554482d43000000000000000000000000000000000000000000000000000000;
    // Collateral type of MAKER deposited collatera. Here: WSTETH
    bytes32 internal ilk_yieldBearing = 0x5753544554482d41000000000000000000000000000000000000000000000000;
    // Token Adapter Module for collateral. Here: WSTETH    
    address internal gemJoinAdapter = 0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2;


    //DYDX Flashloan
    address private constant SOLO = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;


    ISteth internal constant stETH =  ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 internal constant investmentToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    //Referal 
    address private referal = 0x35a83D4C1305451E0448fbCa96cAb29A7cCD0811;
    uint256 private slippageProtection;


    //----------- MAKER INIT    
    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // 100%
    //uint256 internal constant WAD = WAD;

    // Maximum loss on withdrawal from yVault
    //uint256 internal constant MAX_LOSS_BPS = 10000;

    // Wrapped Ether - Used for swaps routing
    //address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // SushiSwap router
    //ISwap internal constant sushiswapRouter = ISwap(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // UniswapV2 router
    ISwap internal constant uniswapV2Router = ISwap(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // UniswapV3 router
    //ISwapRouter internal constant uniswapV3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    //ISwapRouter internal constant uniswapV3Router2 = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    // Provider to read current block's base fee
    IBaseFee internal constant baseFeeProvider = IBaseFee(0xf8d0Ec04e94296773cE20eFbeeA82e76220cD549);

    // Maker Oracle Security Module
    //IOSMedianizer public wantToUSDOSMProxy;
    //IOSMedianizer public yieldBearingToUSDOSMProxy;

    //ETH USDOSMPROXY:
    address public wantToUSDOSMProxy = 0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1;
    //WSTETH does not have a OSM Proxy for now:
    address public yieldBearingToUSDOSMProxy;

    // Use Chainlink oracle to obtain latest want/ETH price
    //AggregatorInterface public chainlinkWantToETHPriceFeed;

    // DAI yVault
    IVault public yVault;

    // Router used for swaps
    //ISwapRouter internal router = uniswapV3Router;
    ISwap internal router = uniswapV2Router;

    // Our vault identifier
    uint256 public cdpId;

    // Our desired collaterization ratio
    uint256 public collateralizationRatio;

    // Allow the collateralization ratio to drift a bit in order to avoid cycles
    uint256 public rebalanceTolerance;

    // Percentage of reinvestment of borrowed investmentToken into yieldBearing
    uint256 public reinvestmentLeverageComponent;
    // Percentage of reinvestment of borrowed investmentToken into yVault is 1-variable.

    // Max acceptable base fee to take more debt or harvest
    uint256 internal maxAcceptableBaseFee;

    // Maximum acceptable loss on investment yVault withdrawal. Default to 0.01%.
    uint256 internal maxLoss;

    // Maximum Single Trade possible
    //uint256 public maxSingleTrade;

    // Repayment below debt floor amount that is partially repaid with free investmentoken and partially flashloan 
    uint256 internal totalRepayAmount;

    // If set to true the strategy will never try to repay debt by selling want
    //bool internal retainDebtFloor;

    // Name of the strategy
    string internal strategyName;

    // ----------------- INIT FUNCTIONS TO SUPPORT CLONING -----------------

    constructor(
        address _vault,
        address _yVault,
        string memory _strategyName
      //  bytes32 _ilk_want,
      //  bytes32 _ilk_yieldBearing,
      //  address _gemJoin
      //  address _wantToUSDOSMProxy
      //  address _yieldBearingToUSDOSMProxy
       // address _chainlinkWantToETHPriceFeed
    ) public BaseStrategy(_vault) {
        _initializeThis(
            _yVault,
            _strategyName
       //     _ilk_want,
       //     _ilk_yieldBearing,
       //     _gemJoin
       //     _wantToUSDOSMProxy
       //     _yieldBearingToUSDOSMProxy
       //     _chainlinkWantToETHPriceFeed
        );
    }

    function initialize(
        address _vault,
        address _yVault,
        string memory _strategyName
    //    bytes32 _ilk_want,
    //    bytes32 _ilk_yieldBearing,
    //    address _gemJoin
    //    address _wantToUSDOSMProxy
    //    address _yieldBearingToUSDOSMProxy
    //    address _chainlinkWantToETHPriceFeed
    ) public {
        // Make sure we only initialize one time
        require(address(yVault) == address(0)); // dev: strategy already initialized

        address sender = msg.sender;

        // Initialize BaseStrategy
        _initialize(_vault, sender, sender, sender);

        // Initialize cloned instance
        _initializeThis(
            _yVault,
            _strategyName
        //    _ilk_want,
        //    _ilk_yieldBearing,
        //    _gemJoin
        //    _wantToUSDOSMProxy
        //    _yieldBearingToUSDOSMProxy
        //    _chainlinkWantToETHPriceFeed
        );
    }

    function _initializeThis(
        address _yVault,
        string memory _strategyName
    //    bytes32 _ilk_want,
    //    bytes32 _ilk_yieldBearing,
    //    address _gemJoin
    //    address _wantToUSDOSMProxy
    //    address _yieldBearingToUSDOSMProxy
    //    address _chainlinkWantToETHPriceFeed
    ) internal {
        yVault = IVault(_yVault);
        strategyName = _strategyName;
        //ilk_want = _ilk_want;
        //ilk_yieldBearing = _ilk_yieldBearing;
        //gemJoinAdapter = _gemJoin;
        //old:
        //wantToUSDOSMProxy = IOSMedianizer(_wantToUSDOSMProxy);
        //yieldBearingToUSDOSMProxy = IOSMedianizer(_yieldBearingToUSDOSMProxy);
        //new: addresses:
        //wantToUSDOSMProxy = _wantToUSDOSMProxy;
        //yieldBearingToUSDOSMProxy = _yieldBearingToUSDOSMProxy;
        //chainlinkWantToETHPriceFeed = AggregatorInterface(_chainlinkWantToETHPriceFeed);

        reinvestmentLeverageComponent = 5000;
    
        //100 = 1%, 
        slippageProtection = 100;

        //1000 ETH maximum trade
        //maxSingleTrade = 1_000 * 1e18;

        // Set health check to health.ychad.eth
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;

        cdpId = MakerDaiDelegateLib.openCdp(ilk_yieldBearing);
        require(cdpId > 0); // dev: error opening cdp

        // Current ratio can drift (collateralizationRatio -f rebalanceTolerance, collateralizationRatio plus rebalanceTolerance)
        // Allow additional 15% in any direction (210, 240) by default
        rebalanceTolerance = (15 * WAD) / 100;

        // Minimum collaterization ratio on YFI-A is 175%
        // Minimum collaterization ratio for WstETH is 160%
        // Use 225% as target - lower?
        collateralizationRatio = (225 * WAD) / 100;

        // If we lose money in yvDAI then we are not OK selling want to repay it
        //retainDebtFloor = false;

        // Define maximum acceptable loss on withdrawal to be 0.01%.
        maxLoss = 100;

        // Set max acceptable base fee to take on more debt to 60 gwei
        //maxAcceptableBaseFee = 60 * 1e9;
        maxAcceptableBaseFee = 1000 * 1e9;
    }

    //we get eth
    receive() external payable {}

    // ----------------- SETTERS & MIGRATION -----------------

/*
    function updateMaxSingleTrade(uint256 _maxSingleTrade) public onlyVaultManagers {
        maxSingleTrade = _maxSingleTrade;
    }

    function updateReferal(address _referal) public onlyEmergencyAuthorized {
        referal = _referal;
    }
*/

    function setWantAndYieldBearingUSDOSMProxy(address _newaddressWant, address _newaddressYieldBearing)
        external
        onlyEmergencyAuthorized
    {
        wantToUSDOSMProxy = _newaddressWant;
        yieldBearingToUSDOSMProxy = _newaddressYieldBearing;
    }



    // Target collateralization ratio to maintain within bounds
    function setCollateralizationRatio(uint256 _collateralizationRatio)
        external
        onlyEmergencyAuthorized
    {
        require(
            _collateralizationRatio.sub(rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(WAD).div(
                    RAY
                )
        ); // dev: desired collateralization ratio is too low
        collateralizationRatio = _collateralizationRatio;
    }

    // Rebalancing bands (collat ratio - tolerance, collat_ratio plus tolerance)
    function setRebalanceTolerance(uint256 _rebalanceTolerance)
        external
        onlyEmergencyAuthorized
    {
        require(
            collateralizationRatio.sub(_rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(WAD).div(
                    RAY
                )
        ); // dev: desired rebalance tolerance makes allowed ratio too low
        rebalanceTolerance = _rebalanceTolerance;
    }


    function setReinvestmentLeverageComponent(uint256 _percentage)
        external
        onlyEmergencyAuthorized
    {
        //_percentage as 95.75% = 9575, 100% = 10000
        require(_percentage <= 10000);
        reinvestmentLeverageComponent = _percentage;
    }

    // Maximum acceptable base fee of current block to take on more debt
    function setMaxAcceptableBaseFee(uint256 _maxAcceptableBaseFee)
        external
        onlyEmergencyAuthorized
    {
        maxAcceptableBaseFee = _maxAcceptableBaseFee;
    }

 /*   // If set to true the strategy will never sell want to repay debts
    function setRetainDebtFloorBool(bool _retainDebtFloor)
        external
        onlyEmergencyAuthorized
    {
        retainDebtFloor = _retainDebtFloor;
    }


    // Max slippage to accept when withdrawing from yVault
    function setMaxLoss(uint256 _maxLoss) external onlyVaultManagers {
        //require(_maxLoss <= MAX_LOSS_BPS); // dev: invalid value for max loss
        maxLoss = _maxLoss;
    }

    // Set slippage protection for Curve
    function setSlippageProtection(uint256 _slippageProtection)
        external
        onlyVaultManagers
    {
        require(_slippageProtection <= 10000);
        slippageProtection = _slippageProtection;
    }


*/


    // Required to move funds to a new cdp and use a different cdpId after migration
    // Should only be called by governance as it will move funds
    function shiftToCdp(uint256 newCdpId) external onlyGovernance {
        MakerDaiDelegateLib.shiftCdp(cdpId, newCdpId);
        cdpId = newCdpId;
    }

    // Move yvDAI funds to a new yVault
    function migrateToNewDaiYVault(IVault newYVault) external onlyGovernance {
        uint256 balanceOfYVaultInvestment = balanceOfYVaultInvestment();
        if (balanceOfYVaultInvestment > 0) {
            yVault.withdraw(balanceOfYVaultInvestment, address(this), maxLoss);
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
/*
    function switchRouter(address _router) external onlyVaultManagers {
        router = ISwapRouter(_router);
    }
*/
    // Allow external debt repayment
    // Attempt to take currentRatio to target c-ratio
    // Passing zero will repay all debt if possible
    function emergencyDebtRepayment(uint256 currentRatio)
        external
        onlyVaultManagers
    {
        _repayDebt(currentRatio);
    }
/*
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

    //Reliable version: estimate ETH from STETH == ETH assumption: 
    function estimatedTotalAssets() public view override returns (uint256) {  //measured in WANT
        return  
                balanceOfWant() //free WANT balance in wallet
                //.add(ethToWant(address(this).balance))  //free ETH balance in wallet
                .add(yieldBearing.getStETHByWstETH(balanceOfYieldBearing().add(balanceOfMakerVault()))) //free yield bearing in case of deposit in vault below makerdao debtfloor; treat steth as eth
                //.add(yieldBearing.getStETHByWstETH(balanceOfMakerVault()))   //Collateral on Maker --> yieldBearing --> WANT 
                .add(_convertInvestmentTokenAmountToWant(balanceOfInvestmentToken()))  // free DAI balance in wallet --> WANT
                .add(_convertInvestmentTokenAmountToWant(_valueOfInvestment()))  //locked yvDAI shares --> DAI --> WANT
                .sub(_convertInvestmentTokenAmountToWant(balanceOfDebt()));  //DAI debt of maker --> WANT
    }



/*
    //Test version: estimate ETH from WSTETH amount USD value from Maker Oracle:
    function estimatedTotalAssets() public view override returns (uint256) {  //measured in WANT
        return
                balanceOfWant() //free WANT balance in wallet
                //.add(ethToWant(address(this).balance))  //free ETH balance in wallet
                .add(balanceOfYieldBearing().mul(_getYieldBearingUSDPrice()).div(_getWantUSDPrice())) //free yield bearing*yieldbearingUSDprice/wantUSDprice
                .add(balanceOfMakerVault().mul(_getYieldBearingUSDPrice()).div(_getWantUSDPrice())) //maker collateral yield bearing*yieldbearingUSDprice/wantUSDprice 
                .add(_convertInvestmentTokenAmountToWant(balanceOfInvestmentToken()))  // free DAI balance in wallet --> WANT
                .add(_convertInvestmentTokenAmountToWant(_valueOfInvestment()))  //locked yvDAI shares --> DAI --> WANT
                .sub(_convertInvestmentTokenAmountToWant(balanceOfDebt()));  //DAI debt of maker --> WANT
    }
*/

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
        (_amountFreed, _loss) = liquidatePosition(_debtOutstanding.add(_profit));
        //(_amountFreed, _loss) = liquidatePosition(Math.min(maxSingleTrade, _debtOutstanding.add(_profit)));
        _debtPayment = Math.min(_debtOutstanding, _amountFreed);
        //Net profit and loss calculation
        if (_loss > _profit) {
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            _profit = _profit.sub(_loss);
            _loss = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // Update accumulated stability fees,  Update the debt ceiling using DSS Auto Line
        MakerDaiDelegateLib.keepBasicMakerHygiene(ilk_yieldBearing);

        //emit Debug(9999, _debtOutstanding);
        // If we have enough want to convert and deposit more into the maker vault, we do it
        if (balanceOfWant() > _debtOutstanding) {
            //Determine amount of Want to Deposit
            //amount initially in want
            //exchange want to yieldBearing to later deposit and overwrite _amount variable to yieldBearing amount
            uint256 _amount = MakerDaiDelegateLib._swapWantToYieldBearing(balanceOfWant().sub(_debtOutstanding), referal);
            //maxSingelTrade integration:
            //uint256 _amount = MakerDaiDelegateLib._swapWantToYieldBearing(Math.min(maxSingleTrade, balanceOfWant().sub(_debtOutstanding)), referal);
            //Check Allowance to lock Collateral 
            _checkAllowance(gemJoinAdapter, address(yieldBearing), _amount);
            _lockCollateralAndMintDai(_amount, _investmentTokenAmountToMint(_amount));
        }
        // Allow the ratio to move a bit in either direction to avoid cycles
        uint256 currentRatio = getCurrentMakerVaultRatio();
        //if current ratio is below goal ratio:
        if (currentRatio < collateralizationRatio.sub(rebalanceTolerance)) {
            _repayDebt(currentRatio);
        } else if (
            currentRatio > collateralizationRatio.add(rebalanceTolerance)
        ) {
            // Mint the maximum DAI possible for the locked collateral            
            _lockCollateralAndMintDai(0, _investmentTokenAmountToMint(balanceOfMakerVault()).sub(balanceOfDebt()));
        }

        // If we have anything left to invest then deposit into the yVault
        _depositInvestmentTokenInYVault();
    }

    function liquidatePosition(uint256 _wantAmountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 collateralPrice = _getYieldBearingUSDPrice();
        //uint256 collateralBalance = balanceOfMakerVault();
        uint256 wantBalance = balanceOfWant();
        uint256 yieldBearingBalance = balanceOfYieldBearing();
        //Check if we can handle it without swapping free yieldBearing or freeing collateral yieldBearing
        if (wantBalance >= _wantAmountNeeded) {
            return (_wantAmountNeeded, 0);
        }
        //Amount of yieldBearing necessary to be swapped to pay off necessary want, minus free want
        //old method: use steth to eth 1:1 relationship
        uint256 yieldBearingAmountToFree = yieldBearing.getWstETHByStETH(_wantAmountNeeded.sub(wantBalance));
        //new method: compare oracle prices: 
        //debugTrace error origin:
        //uint256 yieldBearingAmountToFree = (_wantAmountNeeded.sub(wantBalance)).mul(_getWantUSDPrice()).div(collateralPrice);
        
        // Is there enough free yield bearing to pay off everything?
        if (yieldBearingBalance >= yieldBearingAmountToFree) {
            MakerDaiDelegateLib._swapYieldBearingToWant(yieldBearingAmountToFree, slippageProtection);
            //update free want after liquidating
            wantBalance = balanceOfWant();
            //loss calculation
            if (wantBalance < _wantAmountNeeded) {
                return (wantBalance, _wantAmountNeeded.sub(wantBalance));
            } else {
                return (_wantAmountNeeded, 0);
            }
        }
        // --- Unlocking collateral ---
        // Cannot free more collateral than what is locked; this is in units of yieldBearing
        if (yieldBearingAmountToFree <= yieldBearingBalance) {
            yieldBearingAmountToFree = 0;
        } else {
            yieldBearingAmountToFree = Math.min(yieldBearingAmountToFree.sub(yieldBearingBalance), balanceOfMakerVault());
        }
        //Total Debt to Maker in InvestmentToken
        uint256 totalDebt = balanceOfDebt();
        // If for some reason we do not have debt, make sure the operation does not revert
        if (totalDebt == 0) totalDebt = 1;
        //New Ratio through calculation with terms denominated in investment token
        uint256 yieldBearingAmountToFreeIT = yieldBearingAmountToFree.mul(collateralPrice).div(WAD);
        uint256 collateralIT = balanceOfMakerVault().mul(collateralPrice).div(WAD);
        //New version accounting for investmentToken Investment in yVault. Subtract debt plus liquidate amount from collateral plus investment OR set to Zero.
        uint256 totalPositiveIT = collateralIT.add(_valueOfInvestment());
        uint256 totalNegativeIT = totalDebt.add(yieldBearingAmountToFreeIT);
        
        if (totalPositiveIT > totalNegativeIT) {
            collateralIT = totalPositiveIT.sub(totalNegativeIT);
        } else {
            collateralIT = 0;
        }
        uint256 newRatio = collateralIT.mul(WAD).div(totalDebt);
        //Old version not accounting for investmentToken Investment status
        //uint256 newRatio = collateralIT.sub(yieldBearingAmountToFreeIT).mul(WAD).div(totalDebt);

        //Attempt to repay necessary debt to restore the target collateralization ratio 
        _repayDebt(newRatio);   
        
        if (balanceOfMakerVault() != 0){ 
            yieldBearingAmountToFree = Math.min(yieldBearingAmountToFree, _maxWithdrawal());
            _freeCollateralAndRepayDai(yieldBearingAmountToFree, 0);
        }

        //Swap unlocked collateral and free yieldBearing into want
        MakerDaiDelegateLib._swapYieldBearingToWant(yieldBearingAmountToFree.add(yieldBearingBalance), slippageProtection);
    
        //update free want after liquidating
        wantBalance = balanceOfWant();

        //Scaling withdrawals in case of an estimatedTotalAssets amount below totalDebt to vault to let earlier withdrawers have the same percentage of loss as later:
        totalDebt = vault.strategies(address(this)).totalDebt;
        //scale withdrawal to estimatedTotalAssets of the strategy to give:
        if (totalDebt != _wantAmountNeeded && estimatedTotalAssets() < totalDebt) {
            if (wantBalance > _wantAmountNeeded){
                wantBalance = _wantAmountNeeded;
            }
            wantBalance = wantBalance.mul(estimatedTotalAssets()).div(totalDebt);
        }
        
        //loss calculation and returning liquidated amount
        if (wantBalance < _wantAmountNeeded) {
            return (wantBalance, _wantAmountNeeded.sub(wantBalance));
        } else {
            return (_wantAmountNeeded, 0);
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
            balanceOfYVaultInvestment()
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
    //    if (address(want) == address(WETH)) {
            return _amtInWei;
    //    }

    //    return _amtInWei.mul(WAD).div(uint256(chainlinkWantToETHPriceFeed.latestAnswer()));
    }

    // ----------------- INTERNAL FUNCTIONS SUPPORT -----------------

    function _repayDebt(uint256 currentRatio) internal {
        //Debt denoted in Investment Token
        uint256 currentDebt = balanceOfDebt();
        //emit Debug(4, currentDebt);
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
        uint256 newDebt = currentDebt.mul(currentRatio).div(collateralizationRatio);
        //emit Debug(14, newDebt);

        //amountToRepay denoted in Investment Token    
        uint256 amountToRepay;
        uint256 balanceIT = balanceOfInvestmentToken(); 
        // Maker will revert if the outstanding debt is less than a debt floor
        // called 'dust'. If we are there we need to either pay the debt in full
        // or leave at least 'dust' balance (10,000 DAI for YFI-A), (15,000 DAI for WSTETH)
        // ------ DEBT FLOR ----
        uint256 debtFloor = MakerDaiDelegateLib.debtFloor(ilk_yieldBearing);
        uint256 minimumDebt;
        // ------ DEBT FLOOR CHECK ------------
        //newDebt denoted in Investment Token
        if (newDebt <= debtFloor) {
            //Below Debt Floor --> Need to pay off entire debt!
            //Check available DAI and yvDAI combined is enough to pay back debt fully
            if (_valueOfInvestment().add(balanceIT) >= currentDebt.add(1)) {
                // Pay the entire debt if we have enough investment token; add(1) 1 Wei to stop dust reverting errors
                amountToRepay = currentDebt.add(1);
            } else {
                // Not enough DAI and yvDAI available to pay off debt. Need to unlock collateral.
                // pay just 0.1 cent above debtFloor (best effort without liquidating want)
                minimumDebt = debtFloor.add(1e15);
                amountToRepay = currentDebt.sub(minimumDebt);
            }
            //setting debtFloor = 0 for later use to verify that whole debt needs to be paid off
            debtFloor = 0;
        // --------- NOT NEAR DEBT FLOOR:
        } else {
            // If we are not near the debt floor then just pay the exact amount
            // needed to obtain a healthy collateralization ratio
            amountToRepay = currentDebt.sub(newDebt);
            debtFloor = 1;
            //setting debtFloor = 1 just in case debtFloor is actually 0 from Maker
        }
        //----WITHDRAWING AND PAYMENT
        //Need to withdraw from yVault?
        if (balanceIT < amountToRepay) {
            //Withdraw up to maximum of yvault
            _withdrawFromYVault(amountToRepay.sub(balanceIT));
        }
        //DAI was freed to wallet
        balanceIT = balanceOfInvestmentToken();
        //Repay Debt (max. down to debt floor)
        _repayInvestmentTokenDebt(amountToRepay);
        
        currentDebt = balanceOfDebt();
        //full maker debt paid down, unlock all collateral
        if (currentDebt == 0) {
            minimumDebt = 0;
            //unlock yvault & maker collateral
            _withdrawFromYVault(_valueOfInvestment());
            _freeCollateralAndRepayDai(balanceOfMakerVault(),0);
            return;
        }
        //If not enough free investmentToken after freeing from yvault to repay necessary debt, then need flashloan to unlock collateral
        if (balanceIT < amountToRepay) {
            minimumDebt = currentDebt.sub(newDebt);
            //minimumDebt = difference in what yvault was not able to pay up for
        }
        //If not enough investment & below debtFloor
        if (balanceIT < amountToRepay && debtFloor == 0) {
            minimumDebt = currentDebt;
        }

        //For repayment without enough YVault token OR below debt floor: Flashloan
        if (minimumDebt > 0) {  
            totalRepayAmount = minimumDebt.add(1); 
            _withdrawFromYVault(Math.min(_valueOfInvestment(), totalRepayAmount));
            MakerDaiDelegateLib.initiateFlashLoan(totalRepayAmount, cdpId);
        }
    }


    //DyDx calls this function after doing flash loan
    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public {
        (uint256 flashloanAmount, uint256 repayAmount) = abi.decode(data, (uint256, uint256));
        require(msg.sender == SOLO, "NOT_SOLO");
        MakerDaiDelegateLib.executeFlashloan(
            flashloanAmount,
            2,
            cdpId,
            router,
            repayAmount
        );
    }   

    function _investmentTokenAmountToMint(uint256 _amount) internal returns (uint256) {
        uint256 investmentTokenReserve;
        uint256 investmentTokenBalance = investmentToken.balanceOf(address(this));
        if (investmentTokenBalance < 1000) {
            investmentTokenReserve = 1000 - investmentTokenBalance;
        }

        return _amount.mul(_getYieldBearingUSDPrice()).mul(WAD).div(collateralizationRatio).div(WAD);
    }

    function _withdrawFromYVault(uint256 _amountIT) internal returns (uint256) {
        if (_amountIT == 0) {
            return 0;
        }
        // No need to check allowance because the contract == token
        uint256 balancePrior = balanceOfInvestmentToken();
        uint256 sharesToWithdraw =
            Math.min(_investmentTokenToYShares(_amountIT), balanceOfYVaultInvestment());
        if (sharesToWithdraw == 0) {
            return 0;
        }
        yVault.withdraw(sharesToWithdraw, address(this), maxLoss);
        return balanceOfInvestmentToken().sub(balancePrior);
    }

    function _depositInvestmentTokenInYVault() internal {
        uint256 balanceIT = balanceOfInvestmentToken();
        if (balanceIT > 10000) {
            //emit Debug(2121212, balanceIT);
            //Calculate amount of investmentTokens to convert to want to deposit afterwards as collateral
            balanceIT = balanceIT.mul(reinvestmentLeverageComponent).div(10000);
            //emit Debug(2121213, balanceIT);
            uint256 wantAmountOut = MakerDaiDelegateLib._swapInvestmentTokenToWant(balanceIT, router);
            //Convert investmentToken into yieldBearing & lock as collateral
            //emit Debug(2121214, wantAmountOut);
            _lockCollateralAndMintDai(MakerDaiDelegateLib._swapWantToYieldBearing(wantAmountOut, referal), 0);
            collateralizationRatio = getCurrentMakerVaultRatio();            

            //Rest of investmentToken deposit into yVault
            balanceIT = balanceOfInvestmentToken();
            _checkAllowance(address(yVault), address(investmentToken), balanceIT);
            //yVault.deposit();
            //emit Debug(2121214, balanceIT);
            yVault.deposit(balanceIT);
            //Keep a minimum of 1000 wei of investmenttoken for DYDX flashloan
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
            IERC20(_token).safeApprove(_contract, 0);
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
        if (ySharesToWithdraw > 1000) {
            yVault.withdraw(ySharesToWithdraw, address(this), maxLoss);
            MakerDaiDelegateLib._swapInvestmentTokenToWant(balanceOfInvestmentToken(), router);
        }
    }

    // Returns maximum collateral to withdraw while maintaining the target collateralization ratio
    function _maxWithdrawal() internal view returns (uint256) {
        // Denominated in yieldBearing
        // If there is no debt to repay we can withdraw all the locked collateral
        if (balanceOfDebt() == 0) {
            return balanceOfMakerVault();
        }

        // Min collateral in yieldBearing that needs to be locked with the outstanding debt
        // Allow going to the lower rebalancing band
        uint256 minCollateral =
            collateralizationRatio
                .sub(rebalanceTolerance)
                .mul(balanceOfDebt())
                .mul(WAD)
                .div(_getYieldBearingUSDPrice())
                .div(WAD);

        // If we are under collateralized then it is not safe for us to withdraw anything
        if (minCollateral > balanceOfMakerVault()) {
            return 0;
        }

        return balanceOfMakerVault().sub(minCollateral);
    }

    // ----------------- PUBLIC BALANCES AND CALCS -----------------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfYieldBearing() public view returns (uint256) {
        return yieldBearing.balanceOf(address(this));
    }

    function balanceOfstETH() public view returns (uint256) {
        return stETH.balanceOf(address(this));
    }
/*
    function balanceOfInvestmentToken() public view returns (uint256) {
        return investmentToken.balanceOf(address(this));
    }
*/
    function balanceOfInvestmentToken() public view returns (uint256) {
        uint256 tokenBalance = investmentToken.balanceOf(address(this));
        if (tokenBalance > 1000) {
            tokenBalance = tokenBalance.sub(1000);
        } else {
            tokenBalance = 0;
        }
        return tokenBalance;
    }

    function balanceOfYVaultInvestment() public view returns (uint256) {
        return yVault.balanceOf(address(this));
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
                WAD
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
        uint256 minPrice = MakerDaiDelegateLib.getIlkOSMPrice(ilk_want, wantToUSDOSMProxy);
        //uint256 minPrice = MakerDaiDelegateLib.getSpotPrice(ilk_want);
        // If price is set to 0 then we hope no liquidations are taking place
        // Emergency scenarios can be handled via manual debt repayment or by
        // granting governance access to the CDP
        require(minPrice > 0); // dev: invalid spot price
        return minPrice.mul(RAY).div(MakerDaiDelegateLib.getDaiPar());
    }

    // Returns the minimum price of yieldBearing available in DAI
    function _getYieldBearingUSDPrice() internal view returns (uint256) {
        //No OSM Proxy for WSTETH at the moment, so everything testmode:
        uint256 minPrice = MakerDaiDelegateLib.getIlkOSMPrice(ilk_yieldBearing, yieldBearingToUSDOSMProxy);
        //uint256 minPrice = MakerDaiDelegateLib.getSpotPrice(ilk_yieldBearing);
        // If price is set to 0 then we hope no liquidations are taking place
        // Emergency scenarios can be handled via manual debt repayment or by
        // granting governance access to the CDP
        require(minPrice > 0); // dev: invalid spot price
        return minPrice.mul(RAY).div(MakerDaiDelegateLib.getDaiPar());
    }

    function _valueOfInvestment() internal view returns (uint256) {
        return
            balanceOfYVaultInvestment().mul(yVault.pricePerShare()).div(
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

    function _convertInvestmentTokenAmountToWant(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return _amount.mul(WAD).div(_getWantUSDPrice());
    }
    
/*

    function _convertYieldBearingAmountToWant(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        // WstETH from stETH wrapping/unrapping 1:1
        // treat stETH as 1:1 with ETH/WETH.
        // Reasoning: We are purposely treating stETH and ETH as being equivalent. 
        // This is for a few reasons. The main one is that we do not have a good way to value stETH at any current time without creating exploit routes.
        // Currently you can mint eth for steth but can't burn steth for eth so need to sell. Once eth 2.0 is merged you will be able to burn 1-1 as well.
        // The main downside here is that we will noramlly overvalue our position as we expect stETH to trade slightly below peg.
        // That means we will earn profit on deposits and take losses on withdrawals.
        // This may sound scary but it is the equivalent of using virtualprice in a curve lp. As we have seen from many exploits, virtual pricing is safer than touch pricing.
        
        //yieldBearing amount = _amount --> how much steth would we get?  --> steth 1:1 eth
        return yieldBearing.getStETHByWstETH(_amount);
    }



    function _convertWantAmountToYieldBearingWithLosses(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        
        //Want to WstETH amount through ETH/WETH 1:1 stETH
        //return yieldBearing.getWstETHByStETH(_amount);
        //Alternative: by price oracle
        return amount.mul(_getWantUSDPrice()).div(_getYieldBearingUSDPrice());
    }
    */

}
