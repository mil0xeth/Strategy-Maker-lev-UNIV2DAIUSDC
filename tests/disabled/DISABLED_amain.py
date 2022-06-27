import pytest
from brownie import reverts, chain, Contract, Wei, history, ZERO_ADDRESS
 
def test_collateralization_ratio_changes_with_vault_functions(
   osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert vault.totalAssets() == 0
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    # current coll ratio = 0, target coll ratio = 2
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == False
    assert test_strategy.tendTrigger(1) == False
    
    # Deposit to the vault
    #deposit - user: 50 WETH
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == True
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert test_strategy.collateralizationRatio() == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    #deposit - whale: 250 WETH
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(250 * (10 ** token.decimals()), {"from": token_whale})
    assert test_strategy.collateralizationRatio() == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    #Change coll ratio 2-->3 to check when it changes
    test_strategy.setCollateralizationRatio(3e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 3 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == False
    #Change coll ratio 3 --> to check when it changes
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 3 --> 2 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False    


    #Test Rebalance Tolerance:

    #Change coll ratio 2-->2.12-->2.14 --> 2.15 to check when it changes
    test_strategy.setRebalanceTolerance(0.15*1e18, {"from": gov})
    test_strategy.setCollateralizationRatio(2.12e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.12e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.16e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 2.15
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    #Change DOWN 2.15-->2.14-->2.01 --> 2
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.05e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.05e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.01e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.01e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2.15 --> 2
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False




    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user), user, 100, {'from': user})



def test_collateralization_ratio_changes_with_vault_functions_not_full_withdrawal_user(
    osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert vault.totalAssets() == 0
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    # current coll ratio = 0, target coll ratio = 2
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == False
    assert test_strategy.tendTrigger(1) == False
    
    # Deposit to the vault
    #deposit - user: 50 WETH
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == True
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 2e18
    assert test_strategy.tendTrigger(1) == False

    #deposit - whale: 250 WETH
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(250 * (10 ** token.decimals()), {"from": token_whale})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 2e18
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    #Change coll ratio 2-->3 to check when it changes
    test_strategy.setCollateralizationRatio(3e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 3 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == False
    #Change coll ratio 3 --> to check when it changes
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 3 --> 2 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False    


    #Test Rebalance Tolerance:
    #test_strategy.setRebalanceTolerance()

    #Change coll ratio 2-->2.12-->2.14 --> 2.15 to check when it changes
    test_strategy.setCollateralizationRatio(2.12e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.12e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.16e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 2.15
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    #Change DOWN 2.15-->2.14-->2.01 --> 2
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.05e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.05e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.01e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.01e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2.15 --> 2
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False





    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})

    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user)*0.9, user, 100, {'from': user})


def test_collateralization_ratio_changes_with_vault_functions_not_full_withdrawal_user2(
    osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, strategy, token, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    # Initial ratio is 0 because there is no collateral locked
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert vault.totalAssets() == 0
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    # current coll ratio = 0, target coll ratio = 2
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == False
    assert test_strategy.tendTrigger(1) == False
    
    # Deposit to the vault
    #deposit - user: 50 WETH
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.getCurrentMakerVaultRatio() == 0
    assert test_strategy.harvestTrigger(1) == True
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert test_strategy.collateralizationRatio() == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    #deposit - whale: 250 WETH
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(250 * (10 ** token.decimals()), {"from": token_whale})
    assert test_strategy.collateralizationRatio() == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    # Harvest = send funds through strategy
    chain.sleep(1)
    test_strategy.harvest({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False

    #Change coll ratio 2-->3 to check when it changes
    test_strategy.setCollateralizationRatio(3e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 3 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == False
    #Change coll ratio 3 --> to check when it changes
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 3 --> 2 coll ratio
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False    


    #Test Rebalance Tolerance:
    #test_strategy.setRebalanceTolerance()

    #Change coll ratio 2-->2.12-->2.14 --> 2.15 to check when it changes
    test_strategy.setCollateralizationRatio(2.12e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.12e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.16e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2 --> 2.15
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    #Change DOWN 2.15-->2.14-->2.01 --> 2
    test_strategy.setCollateralizationRatio(2.14e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.14e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.05e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.05e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2.01e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.01e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == False
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2.16e18
    assert test_strategy.tendTrigger(1) == True
    #Tend from 2.15 --> 2
    test_strategy.tend({"from": gov})
    assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 2e18
    assert test_strategy.tendTrigger(1) == False





    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user)*0.95, user, 100, {'from': user})
