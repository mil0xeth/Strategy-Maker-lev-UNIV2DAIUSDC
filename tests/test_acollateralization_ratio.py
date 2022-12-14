import pytest
from brownie import chain, reverts, Wei

wad = 10 ** 18

def calc_expected_collateralization_ratio(strategy, deposit_amount):
    existing_collateral_balance = strategy.balanceOfMakerVault()
    want_per_yield_bearing = strategy.getWantPerYieldBearing()
    existing_collateral = existing_collateral_balance * want_per_yield_bearing / wad
    existing_debt = strategy.balanceOfDebt()
    max_debt_available = strategy.balanceOfDaiAvailableToMint()
    target_collateral_ratio = strategy.collateralizationRatio()
    borrow_amount_needed = deposit_amount * wad / (target_collateral_ratio - wad)
    borrow_amount = min(borrow_amount_needed, max_debt_available)
    expected_collateralization_ratio = (existing_collateral + borrow_amount + deposit_amount) * wad / (existing_debt + borrow_amount)
    return expected_collateralization_ratio


def test_vault_ratio_calculation_on_BIGTIME_total_withdraw(
   router, unirouter, dai, dai_whale, token_whale, vault, test_strategy, yieldBearing, token, amountBIGTIME, amountBIGTIME2, user2, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amountBIGTIME, {"from": user})
    vault.deposit(amountBIGTIME, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == test_strategy.collateralizationRatio())


    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME/2, user, 1000, {"from": user})


    ####### USER 2

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME2)

    token.approve(vault.address, amountBIGTIME2, {"from": user2})
    vault.deposit(amountBIGTIME2, {"from": user2})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == expected_collateralization_ratio)

    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME2/2, user2, 1000, {"from": user2})
    test_strategy.harvest({"from": gov})


    # REPEAT!

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME*0.25)

    token.approve(vault.address, amountBIGTIME*0.25, {"from": user})
    vault.deposit(amountBIGTIME*0.25, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)


    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME*0.25, user, 1000, {"from": user})
    test_strategy.harvest({"from": gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=0.16) == test_strategy.getCurrentMakerVaultRatio())

    #assert token.balanceOf(test_strategy) < 1e18
    assert yieldBearing.balanceOf(test_strategy) < 2e18
    #assert test_strategy.balanceOfMakerVault() == 0
    #assert test_strategy.balanceOfDebt() == 0

    #REPEAT!

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME*0.1)

    token.approve(vault.address, amountBIGTIME*0.1, {"from": user})
    vault.deposit(amountBIGTIME*0.1, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)

    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME*0.1, user, 1000, {"from": user})
    test_strategy.harvest({"from": gov})

    withdraw_tx = vault.withdraw(vault.balanceOf(user), user, 1000, {"from": user})
    withdraw_tx = vault.withdraw(vault.balanceOf(user2), user2, 1000, {"from": user2})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() < 0.00001e18


def test_vault_ratio_calculation_on_BIGTIME_total_withdraw2(
   router, unirouter, dai, dai_whale, token_whale, vault,  test_strategy,  yieldBearing, token, amountBIGTIME, amountBIGTIME2, user2, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME)

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amountBIGTIME, {"from": user})
    vault.deposit(amountBIGTIME, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)

    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME, user, 1000, {"from": user})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() == 0



    ####### USER 2

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME2)

    token.approve(vault.address, amountBIGTIME2, {"from": user2})
    vault.deposit(amountBIGTIME2, {"from": user2})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)


    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME2, user2, 1000, {"from": user2})
    test_strategy.harvest({"from": gov})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() == 0

    # REPEAT!

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME*0.25)

    token.approve(vault.address, amountBIGTIME*0.25, {"from": user})
    vault.deposit(amountBIGTIME*0.25, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)


    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME*0.25, user, 1000, {"from": user})
    test_strategy.harvest({"from": gov})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() == 0

    #REPEAT!

    expected_collateralization_ratio = calc_expected_collateralization_ratio(test_strategy, amountBIGTIME*0.1)

    token.approve(vault.address, amountBIGTIME*0.1, {"from": user})
    vault.deposit(amountBIGTIME*0.1, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == expected_collateralization_ratio)


    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amountBIGTIME*0.1, user, 1000, {"from": user})
    test_strategy.harvest({"from": gov})
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == 0)
    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() == 0





def test_lower_ratio_inside_rebalancing_band_should_not_take_more_debt(
    vault, strategy, token, amount, user, gov, RELATIVE_APPROX
):
    # Deposit to the vault
    strategy.setCollateralizationRatio(1.05e18, {"from": gov})
    assert token.balanceOf(vault) == 0
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest({"from": gov})

    new_ratio = strategy.collateralizationRatio() - strategy.lowerRebalanceTolerance() * 0.99
    strategy.setCollateralizationRatio(new_ratio, {"from": gov})

    # Adjust the position
    strategy.tend({"from": gov})

    # Strategy should restore collateralization ratio to target value
    assert (pytest.approx(strategy.collateralizationRatio(), rel=RELATIVE_APPROX) != strategy.getCurrentMakerVaultRatio())

def test_higher_target_ratio_should_repay_debt(
    vault, strategy, token, amount, user, gov, RELATIVE_APPROX
):
    assert token.balanceOf(vault) == 0
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    harvest_tx = strategy.harvest({"from": gov})
    assert token.balanceOf(vault) == 0


    new_ratio_relative = 1.01

    # In default settings this will be 225 * 1.2 = 270
    strategy.setCollateralizationRatio(
        strategy.collateralizationRatio() * new_ratio_relative, {"from": gov}
    )

    # Adjust the position
    tend_tx = strategy.tend({"from": gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(strategy.collateralizationRatio(), rel=RELATIVE_APPROX) == strategy.getCurrentMakerVaultRatio())

    # Because the target collateralization ratio is higher, a part of the debt
    # will be repaid to maintain a healthy ratio
    # Todo: Add test for debt amounts?


def test_higher_ratio_inside_rebalancing_band_should_not_repay_debt(
    vault, test_strategy, token, amount, user, gov, RELATIVE_APPROX
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})


    new_ratio = ( test_strategy.collateralizationRatio() + test_strategy.upperRebalanceTolerance() * 0.98 )
    test_strategy.setCollateralizationRatio(new_ratio, {"from": gov})

    assert test_strategy.tendTrigger(1) == False

    # Adjust the position
    test_strategy.tend({"from": gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX) != test_strategy.getCurrentMakerVaultRatio())


def test_vault_ratio_calculation_on_withdraw(
   vault,  test_strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (
        pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX)
        == test_strategy.collateralizationRatio()
    )


    # Withdraw 3% of the assets
    withdraw_tx = vault.withdraw(amount * 0.03, user, 1000, {"from": user})

    test_strategy.tend({'from': gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX) == test_strategy.getCurrentMakerVaultRatio())



def test_vault_ratio_calculation_on_very_low_withdraw(
    vault, test_strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == test_strategy.collateralizationRatio())

 
    # Withdraw 0.1% of the assets
    withdraw_tx = vault.withdraw(amount * 0.001, user, 1000, {"from": user})

    test_strategy.tend({'from': gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX) == test_strategy.getCurrentMakerVaultRatio())



def test_vault_ratio_calculation_on_high_withdraw(
    vault,  test_strategy, token,  amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (
        pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX)
        == test_strategy.collateralizationRatio()
    )

    # Withdraw 50% of the assets
    withdraw_tx = vault.withdraw(amount * 0.5, user, 1000, {"from": user})
    test_strategy.tend({'from': gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (
        pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX)
        == test_strategy.getCurrentMakerVaultRatio()
    )


def test_vault_ratio_calculation_on_very_high_withdraw(
    yieldBearing,dai, dai_whale, vault, test_strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (
        pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX)
        == test_strategy.collateralizationRatio()
    )


    # Withdraw 80% of the assets
    withdraw_tx = vault.withdraw(amount * 0.8, user, 1000, {"from": user})
    test_strategy.tend({'from': gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=0.16) == test_strategy.getCurrentMakerVaultRatio())


def test_vault_ratio_calculation_on_almost_total_withdraw(
    yieldBearing,dai, dai_whale, vault, router,  test_strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (
        pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX)
        == test_strategy.collateralizationRatio()
    )

    # Withdraw 50% of the assets
    withdraw_tx = vault.withdraw(amount * 0.95, user, 100, {"from": user})
    test_strategy.tend({'from': gov})

    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX) != test_strategy.getCurrentMakerVaultRatio())


def test_vault_ratio_calculation_on_total_withdraw(
    yieldBearing,dai, dai_whale, token_whale, vault, test_strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})

    # Collateral ratio should be the target ratio set
    assert (
        pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX)
        == test_strategy.collateralizationRatio()
    )

    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amount, user, 100, {"from": user})
    test_strategy.tend({'from': gov})

    # Strategy should have 0 collateralization ratio to target value on withdraw
    assert (
        pytest.approx(0, rel=RELATIVE_APPROX)
        == test_strategy.getCurrentMakerVaultRatio()
    )

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() == 0


def test_vault_ratio_calculation_on_sandwiched_total_withdraw(
    yieldBearing,token_whale, vault,  test_strategy, token,  amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    #sandwich:
    sandwich = "1000 ether"
    token.approve(vault.address, sandwich, {"from": token_whale})
    vault.deposit(sandwich, {"from": token_whale})

    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    withdraw_tx = vault.withdraw(vault.balanceOf(token_whale)*0.3, token_whale, 10000, {"from": token_whale})
    # Strategy should restore collateralization ratio to target value on withdraw
    assert (pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX) != test_strategy.getCurrentMakerVaultRatio())

    # Withdraw 100% of the assets, with 0.1% maxLoss
    withdraw_tx = vault.withdraw(amount, user, 1000, {"from": user})
    withdraw_tx = vault.withdraw(vault.balanceOf(token_whale), token_whale, 1000, {"from": token_whale})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == 0
    assert test_strategy.estimatedTotalAssets() < 0.001e18




def test_ratio_lower_than_liquidation_should_revert(strategy, gov):
    with reverts():
        strategy.setCollateralizationRatio(1e18, {"from": gov})



