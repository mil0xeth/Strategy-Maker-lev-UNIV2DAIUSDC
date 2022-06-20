import pytest

from brownie import chain


def test_revoke_strategy_from_vault(
    chain, token, vault, strategy, amount, user, gov, RELATIVE_APPROX_LOSSY
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY) == amount

    vault.revokeStrategy(strategy.address, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert vault.strategies(strategy).dict()["debtRatio"] == 0
    assert vault.strategies(strategy).dict()["totalDebt"] == 0
    assert pytest.approx(token.balanceOf(vault.address), rel=RELATIVE_APPROX_LOSSY) == amount


def test_revoke_strategy_from_strategy(
    chain, token, vault, strategy, amount, user, gov, RELATIVE_APPROX_LOSSY
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY) == amount

    strategy.setEmergencyExit({"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert vault.strategies(strategy).dict()["debtRatio"] == 0
    assert vault.strategies(strategy).dict()["totalDebt"] == 0
    assert pytest.approx(token.balanceOf(vault.address), rel=RELATIVE_APPROX_LOSSY) == amount


def test_revoke_with_profit(
    token, dai, vault, strategy, token_whale, gov, borrow_token, borrow_whale, yvault,
):
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(20 * (10 ** token.decimals()), {"from": token_whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    assert vault.strategies(strategy).dict()["totalGain"] == 0
    assert vault.strategies(strategy).dict()["debtRatio"] == 10_000
    assert vault.strategies(strategy).dict()["totalDebt"]/1e18 == 20

    # Send some profit to yvault
    borrow_token.transfer(yvault, 10_000_000 * (10 ** borrow_token.decimals()), {"from": borrow_whale})
    vault.revokeStrategy(strategy, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    assert vault.strategies(strategy).dict()["totalGain"] > 0
    assert vault.strategies(strategy).dict()["debtRatio"] == 0
    assert vault.strategies(strategy).dict()["totalDebt"] == 0
