import pytest
from brownie import chain, reverts, Wei

wad = 10 ** 18


def DISABLED_flashloan_attack(
    gov, chain, accounts, token, vault, strategy, user, amount, RELATIVE_APPROX, token_whale, strategist, router, unirouter, dai, dai_whale, yieldBearing, amountBIGTIME, amountBIGTIME2, user2, RELATIVE_APPROX_LOSSY, flashloan_attacker
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Transfer 200K DAI tokens to deposit in vault
    token.transfer(flashloan_attacker.address, amountBIGTIME, {'from': dai_whale})
    
    # Deposit all to vault
    flashloan_attacker.depositAll({'from': strategist})

    # Transfer 1M DAI tokens to attacker to prepare for attack
    token.transfer(flashloan_attacker.address, amountBIGTIME2, {'from': dai_whale})

    # Attack; Withdraw after forcing a pool imbalance
    flashloan_attacker.performAttack({'from': strategist})

    flashloan_attacker_balance = token.balanceOf(flashloan_attacker.address)
    print(flashloan_attacker_balance)

    assert True == False

    # harvest
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # tend({"from": gov})
    strategy.tend({"from": gov})

    # withdrawal
    vault.withdraw({"from": user})
    assert ( pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before )


def test_pool_drain_attack(
    gov, chain, accounts, token, partnerToken, usdc_whale, vault, strategy, user, amount, RELATIVE_APPROX, token_whale, strategist, router, unirouter, dai, dai_whale, yieldBearing, amountBIGTIME, amountBIGTIME2, user2, RELATIVE_APPROX_LOSSY, flashloan_attacker
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Transfer 200K DAI tokens to deposit in vault
    token.transfer(flashloan_attacker.address, amountBIGTIME, {'from': dai_whale})
    
    # Deposit all to vault
    flashloan_attacker.depositAll({'from': strategist})

    # Transfer 1M DAI tokens to attacker to prepare for attack
    token.transfer(flashloan_attacker.address, amountBIGTIME2, {'from': dai_whale})

    # Transfer 1M DAI tokens to attacker to prepare for attack
    partnerToken.transfer(flashloan_attacker.address, amountBIGTIME2 / 10 ** 12, {'from': usdc_whale})


    # Attack; Withdraw after forcing a pool imbalance
    flashloan_attacker.performPoolDrainAttack({'from': strategist})

    flashloan_attacker_balance = token.balanceOf(flashloan_attacker.address)
    print(flashloan_attacker_balance)

    assert True == False

    # harvest
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # tend({"from": gov})
    strategy.tend({"from": gov})

    # withdrawal
    vault.withdraw({"from": user})
    assert ( pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before )
