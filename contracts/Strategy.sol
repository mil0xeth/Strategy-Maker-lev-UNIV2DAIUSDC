// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/math/Math.sol";
import {
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./libraries/MakerDaiDelegateLib.sol";

import "../interfaces/yearn/IBaseFee.sol";
import "../interfaces/yearn/IVault.sol";

import "../interfaces/GUNI/GUniPool.sol";

contract Strategy is BaseStrategy {
    using Address for address;

    //event Debug(uint256 _number, uint _value);

    enum Action {WIND, UNWIND}

    //GUNIDAIUSDC1 - Gelato Uniswap DAI/USDC LP - 0.05% fee
    GUniPool internal constant yieldBearing = GUniPool(0xAbDDAfB225e10B90D798bB8A886238Fb835e2053);
    bytes32 internal constant ilk_yieldBearing = 0x47554e49563344414955534443312d4100000000000000000000000000000000;
    address internal constant gemJoinAdapter = 0xbFD445A97e7459b0eBb34cfbd3245750Dba4d7a4;
    
    //GUNIDAIUSDC2 - Gelato Uniswap DAI/USDC2 LP 2 - 0.01% fee
    //GUniPool internal constant yieldBearing = GUniPool(0x50379f632ca68D36E50cfBC8F78fe16bd1499d1e)
    //bytes32 internal constant ilk_yieldBearing = 0x47554e49563344414955534443322d4100000000000000000000000000000000;
    //address internal constant gemJoinAdapter = 0xA7e4dDde3cBcEf122851A7C8F7A55f23c0Daf335;

    //Flashmint:
    address internal constant flashmint = 0x1EB4CF3A948E7D72A198fe073cCb8C7a948cD853;

    //DYDX Flashloan
    //address internal constant SOLO = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    IERC20 internal constant investmentToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    //----------- MAKER INIT    
    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // Provider to read current block's base fee
    IBaseFee internal constant baseFeeProvider = IBaseFee(0xf8d0Ec04e94296773cE20eFbeeA82e76220cD549);

    // maker vault identifier
    uint256 public cdpId;

    //Desired collaterization ratio
    //Directly affects the leverage multiplier for every investment to leverage up the Maker vault with yieldBearing: 
    //Off-chain calculation geometric converging series: sum(1/1.02^n)-1 for n=0-->infinity --> for 102% collateralization ratio = 50x leverage.
    uint256 public collateralizationRatio;

    // Allow the collateralization ratio to drift a bit in order to avoid cycles
    uint256 public rebalanceTolerance;

    // Max acceptable base fee to take more debt or harvest
    uint256 internal maxAcceptableBaseFee;

    // Maximum Single Trade possible
    uint256 public maxSingleTrade;

    // Name of the strategy
    string internal strategyName;

    // ----------------- INIT FUNCTIONS TO SUPPORT CLONING -----------------

    constructor(
        address _vault,
        string memory _strategyName
      //  bytes32 _ilk_yieldBearing,
      //  address _gemJoin
    ) public BaseStrategy(_vault) {
        _initializeThis(
            _strategyName
       //     _ilk_yieldBearing,
       //     _gemJoin
        );
    }

    function initialize(
        address _vault,
        string memory _strategyName
    //    bytes32 _ilk_yieldBearing,
    //    address _gemJoin
    ) public {
        address sender = msg.sender;
        // Initialize BaseStrategy
        _initialize(_vault, sender, sender, sender);
        // Initialize cloned instance
        _initializeThis(
            _strategyName
        //    _ilk_yieldBearing,
        //    _gemJoin
        );
    }

    function _initializeThis(
        string memory _strategyName
    //    bytes32 _ilk_yieldBearing,
    //    address _gemJoin
    ) internal {
        strategyName = _strategyName;
        //ilk_yieldBearing = _ilk_yieldBearing;
        //gemJoinAdapter = _gemJoin;

        //10M$ dai or usdc maximum trade
        maxSingleTrade = 10_000_000 * 1e18;

        // Set health check to health.ychad.eth
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;

        cdpId = MakerDaiDelegateLib.openCdp(ilk_yieldBearing);
        require(cdpId > 0); // dev: error opening cdp

        // Current ratio can drift (collateralizationRatio -f rebalanceTolerance, collateralizationRatio plus rebalanceTolerance)
        // Allow additional 0.005 in any direction (1035, 1045) by default
        rebalanceTolerance = (5 * WAD) / 1000;

        // Minimum collateralization ratio for GUNIV3DAIUSDC is 102%
        collateralizationRatio = (103 * WAD) / 100;

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
        require(_collateralizationRatio.sub(rebalanceTolerance) >= MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(WAD).div(RAY)); // dev: desired collateralization ratio is too low
        collateralizationRatio = _collateralizationRatio;
    }

    // Rebalancing bands (collat ratio - tolerance, collat_ratio plus tolerance)
    function setRebalanceTolerance(uint256 _rebalanceTolerance)
        external
        onlyEmergencyAuthorized
    {
        require(collateralizationRatio.sub(_rebalanceTolerance) >= MakerDaiDelegateLib.getLiquidationRatio(ilk_yieldBearing).mul(WAD).div(RAY)); // dev: desired rebalance tolerance makes allowed ratio too low
        rebalanceTolerance = _rebalanceTolerance;
    }

    // Required to move funds to a new cdp and use a different cdpId after migration
    // Should only be called by governance as it will move funds
    function shiftToCdp(uint256 newCdpId) external onlyGovernance {
        MakerDaiDelegateLib.shiftCdp(cdpId, newCdpId);
        cdpId = newCdpId;
    }
/*
    // Allow address to manage Maker's CDP
    function grantCdpManagingRightsToUser(address user, bool allow)
        external
        onlyGovernance
    {
        MakerDaiDelegateLib.allowManagingCdp(cdpId, user, allow);
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
*/


    // ******** OVERRIDEN METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return strategyName;
    }

    function estimatedTotalAssets() public view override returns (uint256) {  //measured in WANT
        return  
                balanceOfWant() //free WANT balance in wallet
                .add(balanceOfYieldBearing().add(balanceOfMakerVault()).mul(getWantPerYieldBearing()).div(WAD))
                .sub(balanceOfDebt());
                //want=usdc:
                //.add(_convertInvestmentTokenAmountToWant(balanceOfInvestmentToken()))  // free DAI balance in wallet --> WANT
                //.sub(_convertInvestmentTokenAmountToWant(balanceOfDebt()));  //DAI debt of maker --> WANT
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
        uint256 totalAssetsAfterProfit = estimatedTotalAssets();
        _profit = totalAssetsAfterProfit > totalDebt 
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;
        uint256 _amountFreed;
        //(_amountFreed, _loss) = liquidatePosition(_debtOutstanding.add(_profit));
        (_amountFreed, _loss) = liquidatePosition(Math.min(maxSingleTrade, _debtOutstanding.add(_profit)));
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
        // If we have enough want to convert and deposit more into the maker vault, we do it
        if (balanceOfWant() > _debtOutstanding) {
            MakerDaiDelegateLib.wind(Math.min(maxSingleTrade, balanceOfWant().sub(_debtOutstanding)), collateralizationRatio, cdpId);
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

    }

    function liquidatePosition(uint256 _wantAmountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = balanceOfWant();
        //Check if we can handle it without swapping free yieldBearing or freeing collateral yieldBearing
        if (wantBalance >= _wantAmountNeeded) {
            return (_wantAmountNeeded, 0);
        }
        //Not enough want to pay _wantAmountNeeded --> unwind position
        MakerDaiDelegateLib.unwind(_wantAmountNeeded, collateralizationRatio, cdpId);

        //update free want after liquidating
        wantBalance = balanceOfWant();
        
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
        return _amtInWei;
    }

    // ----------------- INTERNAL FUNCTIONS SUPPORT -----------------
    function _repayDebt(uint256 currentRatio) internal {
        uint256 currentDebt = balanceOfDebt();
        if (currentRatio > collateralizationRatio || currentDebt == 0) {
            return;
        }
        MakerDaiDelegateLib.unwind(0, collateralizationRatio, cdpId);
    }

    //Flashmint Callback:
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(msg.sender == flashmint);
        require(initiator == address(this));
        (Action action, uint256 _cdpId, uint256 _wantAmountInitialOrRequested, uint256 flashloanAmount, uint256 _collateralizationRatio) = abi.decode(data, (Action, uint256, uint256, uint256, uint256));
        //amount = flashloanAmount, then add fee
        amount = amount.add(fee);
        _checkAllowance(address(flashmint), address(investmentToken), amount);
        if (action == Action.WIND) {
            MakerDaiDelegateLib._wind(_cdpId, amount, _wantAmountInitialOrRequested, _collateralizationRatio);
        } else if (action == Action.UNWIND) {
            MakerDaiDelegateLib._unwind(_cdpId, amount, _wantAmountInitialOrRequested, _collateralizationRatio);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /*
    //DYDX Flashloan Callback for testing purposes - flashmint works flawlessly, but induces event scoping issues during debugging in brownie
    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) external {
        (Action action, uint256 _cdpId, uint256 _wantAmountInitialOrRequested, uint256 _flashloanAmount, uint256 _collateralizationRatio) = abi.decode(data, (Action, uint256, uint256, uint256, uint256));
        if (action == Action.WIND) {
            MakerDaiDelegateLib._wind(_cdpId, _flashloanAmount.add(2), _wantAmountInitialOrRequested, _collateralizationRatio);
        } else if (action == Action.UNWIND) {
            MakerDaiDelegateLib._unwind(_cdpId, _flashloanAmount.add(2), _wantAmountInitialOrRequested, _collateralizationRatio);
        }
    }   
    */

    function _investmentTokenAmountToMint(uint256 _amount) internal returns (uint256) {
        return _amount.mul(getWantPerYieldBearing()).mul(WAD).div(collateralizationRatio).div(WAD);
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

    // ----------------- PUBLIC BALANCES AND CALCS -----------------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfYieldBearing() public view returns (uint256) {
        return yieldBearing.balanceOf(address(this));
    }

    //get amount of Want in Wei that is received for 1 yieldBearing
    function getWantPerYieldBearing() public view returns (uint256){
        (uint256 wantUnderlyingBalance, uint256 otherTokenUnderlyingBalance) = yieldBearing.getUnderlyingBalances();
        return (wantUnderlyingBalance.mul(WAD).add(otherTokenUnderlyingBalance.mul(WAD).mul(WAD).div(1e6))).div(yieldBearing.totalSupply());
    }

    /*
    //want=usdc
    function balanceOfInvestmentToken() public view returns (uint256) {
        return investmentToken.balanceOf(address(this));
    }
    //DYDX requires a minimum of a few wei to use Flashloan for investmentToken. Create 1000 wei floor of investmentToken to allow flashloan anytime:
    function balanceOfInvestmentToken() public view returns (uint256) {
        uint256 tokenBalance = investmentToken.balanceOf(address(this));
        if (tokenBalance > 1000) {
            tokenBalance = tokenBalance.sub(1000);
        } else {
            tokenBalance = 0;
        }
        return tokenBalance;
    }
    */

    function balanceOfDebt() public view returns (uint256) {
        return MakerDaiDelegateLib.debtForCdp(cdpId, ilk_yieldBearing);
    }

    // Returns collateral balance in the vault
    function balanceOfMakerVault() public view returns (uint256) {
        return MakerDaiDelegateLib.balanceOfCdp(cdpId, ilk_yieldBearing);
    }

    // Effective collateralization ratio of the vault
    function getCurrentMakerVaultRatio() public view returns (uint256) {
        return MakerDaiDelegateLib.getPessimisticRatioOfCdpWithExternalPrice(cdpId,ilk_yieldBearing,getWantPerYieldBearing(),WAD);
    }

    // Check if current block's base fee is under max allowed base fee
    function isCurrentBaseFeeAcceptable() internal view returns (bool) {
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
    /*
    function _convertInvestmentTokenAmountToWant(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        //want=dai:
        return _amount;
        //want=usdc:
        //return _amount.div(1e12);
    }
    */

}
