import brownie
import pytest
from brownie import chain, reverts, Wei

wad = 10 ** 18


def test_flashloan_attack_when_levered_up(
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

    # Lever up; Open the maker position
    chain.sleep(1)
    strategy.harvest({"from": gov})

    # Transfer 1M DAI tokens to attacker to prepare for attack
    token.transfer(flashloan_attacker.address, amountBIGTIME2, {'from': dai_whale})

    # Attack; Withdraw after forcing a pool imbalance
    with brownie.reverts(""):
        flashloan_attacker.performAttack({'from': strategist})