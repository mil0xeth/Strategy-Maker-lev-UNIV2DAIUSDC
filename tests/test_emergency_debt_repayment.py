import pytest
from brownie import chain, reverts, Wei


def test_passing_zero_should_repay_all_debt(
    wsteth, vault, strategy, token, token_whale, user, gov, dai, dai_whale, yvDAI, RELATIVE_APPROX_LOSSY
):
    amount = 1_000 * (10 ** token.decimals())

    # Deposit to the vault
    token.approve(vault.address, amount, {"from": token_whale})
    vault.deposit(amount, {"from": token_whale})

    # Send funds through the strategy
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert strategy.balanceOfDebt() > 0

    # Send some profit to yVault
    dai.transfer(yvDAI, yvDAI.totalAssets() * 0.009, {"from": dai_whale})

    # Harvest 2: Realize profit
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)

    prev_collat = strategy.balanceOfMakerVault()
    strategy.emergencyDebtRepayment(0, {"from": vault.management()})

    # All debt is repaid and collateral is left untouched
    assert strategy.balanceOfDebt() == 0
    #strategy unlocks all collateral if there is not enough to take debt
    #assert strategy.balanceOfMakerVault() == prev_collat
    assert strategy.balanceOfMakerVault() == 0
    assert pytest.approx(wsteth.balanceOf(strategy) == prev_collat, rel=RELATIVE_APPROX_LOSSY)

    # Re-harvest with same funds
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert strategy.balanceOfDebt() > 0
    assert strategy.balanceOfMakerVault() > 0
    assert wsteth.balanceOf(strategy)/1e18 < 1 


def test_passing_zero_should_repay_all_debt_then_new_deposit_create_debt_again(
    wsteth, vault, test_strategy, token, token_whale, user, gov, dai, dai_whale, yvDAI, RELATIVE_APPROX_LOSSY
):
    amount = 1_000 * (10 ** token.decimals())

    # Deposit to the vault
    token.approve(vault.address, amount, {"from": token_whale})
    vault.deposit(amount, {"from": token_whale})

    # Send funds through the strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert test_strategy.balanceOfDebt() > 0

    # Send some profit to yVault
    dai.transfer(yvDAI, yvDAI.totalAssets() * 0.009, {"from": dai_whale})

    # Harvest 2: Realize profit
    test_strategy.harvest({"from": gov})
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)

    prev_collat = test_strategy.balanceOfMakerVault()
    test_strategy.emergencyDebtRepayment(0, {"from": vault.management()})

    # All debt is repaid and collateral is left untouched
    assert test_strategy.balanceOfDebt() == 0
    #strategy unlocks all collateral if there is not enough to take debt
    #assert strategy.balanceOfMakerVault() == prev_collat
    assert pytest.approx(wsteth.balanceOf(test_strategy) == prev_collat, rel=RELATIVE_APPROX_LOSSY)

    ##Deposit AGAIN, test for debt

    # Deposit to the vault
    token.approve(vault.address, amount, {"from": token_whale})
    vault.deposit(amount, {"from": token_whale})

     # Send funds through the strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert pytest.approx(test_strategy.balanceOfMakerVault()/test_strategy.collateralizationRatio()*test_strategy._getPrice() == test_strategy.balanceOfDebt(), rel=RELATIVE_APPROX_LOSSY)
    assert test_strategy.balanceOfDebt() > 0
    assert test_strategy.balanceOfMakerVault() > 0
    assert wsteth.balanceOf(test_strategy)/1e18 < 1 

def test_passing_value_over_collat_ratio_does_nothing(
    vault, strategy, token, amount, user, gov
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    # Send funds through the strategy
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert strategy.balanceOfDebt() > 0

    prev_debt = strategy.balanceOfDebt()
    prev_collat = strategy.balanceOfMakerVault()
    c_ratio = strategy.collateralizationRatio()
    strategy.emergencyDebtRepayment(c_ratio + 1, {"from": vault.management()})

    # Debt and collat remain the same
    assert strategy.balanceOfDebt() == prev_debt
    assert strategy.balanceOfMakerVault() == prev_collat


def test_from_ratio_adjusts_debt(
    vault, strategy, token, amount, user, gov, RELATIVE_APPROX
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    # Send funds through the strategy
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert strategy.balanceOfDebt() > 0

    prev_debt = strategy.balanceOfDebt()
    prev_collat = strategy.balanceOfMakerVault()
    c_ratio = strategy.collateralizationRatio()
    strategy.emergencyDebtRepayment(c_ratio * 0.7, {"from": vault.management()})

    # Debt is partially repaid and collateral is left untouched
    assert (
        pytest.approx(strategy.balanceOfDebt(), rel=RELATIVE_APPROX) == prev_debt * 0.7
    )
    assert strategy.balanceOfMakerVault() == prev_collat
