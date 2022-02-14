import pytest
from brownie import reverts, chain, Contract, Wei, history, ZERO_ADDRESS
 
def test_collateralization_ratio_changes_with_vault_functions(
    StableSwapSTETH, osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, wsteth, steth, strategy, token, yvault, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    test_strategy.setReinvestmentLeverageComponent(0, {'from': gov})
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




    #setLeverage to 50%
    test_strategy.setReinvestmentLeverageComponent(5000, {'from': gov})
    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    #assert pytest.approx(test_strategy.balanceOfMakerVault() - wsteth.getWstETHByStETH(latestdeposit/(collratiobefore/1e18)*test_strategy.reinvestmentLeverageComponent()/10000), rel=RELATIVE_APPROX_LOSSY) == collbefore
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user), user, 100, {'from': user})



def test_collateralization_ratio_changes_with_vault_functions_not_full_withdrawal_user(
    StableSwapSTETH, osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, wsteth, steth, strategy, token, yvault, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    test_strategy.setReinvestmentLeverageComponent(0, {'from': gov})
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




    #setLeverage to 50%
    test_strategy.setReinvestmentLeverageComponent(5000, {'from': gov})
    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    #assert pytest.approx(test_strategy.balanceOfMakerVault() - wsteth.getWstETHByStETH(latestdeposit/(collratiobefore/1e18)*test_strategy.reinvestmentLeverageComponent()/10000), rel=RELATIVE_APPROX_LOSSY) == collbefore
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user)*0.9, user, 100, {'from': user})


def test_collateralization_ratio_changes_with_vault_functions_not_full_withdrawal_user2(
    StableSwapSTETH, osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, wsteth, steth, strategy, token, yvault, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):

    test_strategy = strategy
    test_strategy.setReinvestmentLeverageComponent(0, {'from': gov})
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




    #setLeverage to 50%
    test_strategy.setReinvestmentLeverageComponent(5000, {'from': gov})
    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    #assert pytest.approx(test_strategy.balanceOfMakerVault() - wsteth.getWstETHByStETH(latestdeposit/(collratiobefore/1e18)*test_strategy.reinvestmentLeverageComponent()/10000), rel=RELATIVE_APPROX_LOSSY) == collbefore
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    withdraw_user = vault.withdraw(vault.balanceOf(user)*0.95, user, 100, {'from': user})



def test_leveraging(
    StableSwapSTETH, osmProxy_want, osmProxy_yieldBearing, custom_osm, dai, dai_whale, token_whale, vault, wsteth, steth, test_strategy, token, yvault, amount, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
):
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    #start at 2 coll ratio with 0 WETH deposited
    #setLeverage to 50%
    test_strategy.setReinvestmentLeverageComponent(5000, {'from': gov})
    #deposit - whale: 100 WETHID
    latestdeposit = 100e18
    collratiobefore = test_strategy.collateralizationRatio()
    collbefore = test_strategy.balanceOfMakerVault()
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(latestdeposit, {"from": token_whale})
    #need to harvest
    chain.sleep(1)
    firstlevharvest = test_strategy.harvest({"from": gov})
    #assert pytest.approx(test_strategy.balanceOfMakerVault() - wsteth.getWstETHByStETH(latestdeposit/(collratiobefore/1e18)*test_strategy.reinvestmentLeverageComponent()/10000), rel=RELATIVE_APPROX_LOSSY) == collbefore
    assert test_strategy.balanceOfMakerVault() > collbefore
    #withdraw
    withdraw_whale = vault.withdraw(vault.balanceOf(token_whale), token_whale, 100, {'from': token_whale})

    #deposit user
    # Deposit to the vault
    #deposit - user: 50 WETH
    test_strategy.setCollateralizationRatio(2e18, {"from": gov})
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert test_strategy.collateralizationRatio() == 2e18
    assert test_strategy.tendTrigger(1) == False


    withdraw_user = vault.withdraw(vault.balanceOf(user), user, 100, {'from': user})
    
    assert 0 == 1

    #assert test_strategy.collateralizationRatio() == 2e18
    #assert test_strategy.getCurrentMakerVaultRatio() == 2e18
    #assert test_strategy.tendTrigger(1) == False




    #SIMULATE LOSS OF Collateral Value by freeing Collateral and transfering it away
    #Simulate 10% price drawdown
    #approve?
    #wsteth.approve(token_whale, 2 ** 256 - 1, {"from": test_strategy})
    drawdown = 0.1
    valueOfCollateralBefore = test_strategy.balanceOfMakerVault()
    test_strategy.freeCollateral(test_strategy.balanceOfMakerVault()*drawdown, 0)

    wsteth.transfer(token_whale, wsteth.balanceOf(test_strategy), {'from': test_strategy})
    assert wsteth.balanceOf(test_strategy) < 10000
    assert test_strategy.balanceOfMakerVault() < valueOfCollateralBefore






    #Get yieldBearing price
    #eth_price = osmProxy_want.read()[0]
    #wsteth_price = test_strategy._getPrice()
    
    #set Custom OSM Proxy to manipulate yieldBearing Price:
    #custom_osm.setCurrentPrice(wsteth_price, False)
    #test_strategy.setYieldBearingToUSDOSMProxy(custom_osm)    

    #Price goes up 50%
    #wsteth_price = wsteth_price*1.5
    #custom_osm.setCurrentPrice(wsteth_price, False)
    #assert test_strategy._getPrice() == wsteth_price
    #assert pytest.approx(test_strategy.collateralizationRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18
    #assert pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX_LOSSY) == 3e18


    #Price goes down 50%
    #wsteth_price = wsteth_price*0.5
    #custom_osm.setCurrentPrice(wsteth_price, False)
    #assert test_strategy._getPrice() == wsteth_price

    #What happens to collateralization ratio?

    # current coll ratio = 2, target coll ratio = 2
    #assert (pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == test_strategy.collateralizationRatio())

    #harvest --- adjust according to coll ratio

    #tend --- adjusts according to coll ratio

    #withdraw

    #setcollateralizationratio

    #change how much money available


    #price change: harvest
    #price change: tend
    #price change: deposit
    #price change: withdraw

    

    

    #shares_before = yvault.balanceOf(test_strategy)
    ###### THROWAWAY YVAULT TOKENS
    #yvault.approve(token_whale, 2 ** 256 - 1, {"from": test_strategy})
    #yvault.transfer(token_whale, yvault.balanceOf(test_strategy)*0.8, {"from": test_strategy})
    #assert yvault.balanceOf(test_strategy) == shares_before*0.8

    # Withdraw 100% of the assets, accept major losses
    #withdraw_tx = vault.withdraw(amount*0.3, user, 10000, {"from": user})

    # Strategy should have 0 collateralization ratio to target value on withdraw
    #assert (
    #    pytest.approx(0, rel=RELATIVE_APPROX)
    #    == test_strategy.getCurrentMakerVaultRatio()
    #)








def test_eth_weth_steth_wsteth_wrapping_trading(accounts, ethwrapping, StableSwapSTETH, steth, wsteth, Strategy, token, token_whale, MakerDaiDelegateClonerChoice, strategist, yieldBearingToken, productionVault, yvault, ilk_want, ilk_yieldBearing, gemJoinAdapter, osmProxy_want, osmProxy_yieldBearing, price_oracle_want_to_eth):
    vault = productionVault
    gov = vault.governance()

    cloner = strategist.deploy(
        MakerDaiDelegateClonerChoice,
        vault,
        yvault,
        "Strategy-Maker-lev-wstETH",
        ilk_want,
        ilk_yieldBearing,
        gemJoinAdapter,
    #    osmProxy_want,
    #    osmProxy_yieldBearing,
    #    price_oracle_want_to_eth
    )

    original_strategy_address = history[-1].events["Deployed"]["original"]
    strategy = Strategy.at(original_strategy_address)

    # White-list the strategy in the OSM!
    #osmProxy_want.setAuthorized(strategy, {"from": gov})
    #osmProxy_yieldBearing.setAuthorized(strategy, {"from": gov})

    # Reduce other strategies debt allocation
    for i in range(0, 20):
        strat_address = vault.withdrawalQueue(i)
        if strat_address == ZERO_ADDRESS:
            break

        vault.updateStrategyDebtRatio(strat_address, 0, {"from": gov})

    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 0, {"from": gov})

    #Throw away tokens from vault:
    token.approve(token_whale, 2 ** 256 - 1, {"from": vault})
    token.transfer(token_whale, token.balanceOf(vault), {"from": vault})
    assert token.balanceOf(vault) == 0

    #Deposit 250 want tokens to vault
    token.approve(vault, 2 ** 256 - 1, {"from": token_whale})
    vault.deposit(250 * (10 ** token.decimals()), {"from": token_whale})

    #Harvest: Vault --> Strategy --> Maker allocation

    harvest_tx = strategy.harvest({"from": gov})
    #Collateral is there: reformulate into wsteth
    assert strategy.balanceOfMakerVault()/1e18 > 200
    #Borrowing happened
    assert yvault.balanceOf(strategy) > 0

    chain.sleep(60 * 60 * 24 * 2)
    chain.mine(1)

    slippageProtectionOut = 50
    #eth to weth wrapping and unwrapping
    assert token_whale.balance()/1e18 > 10
    balanceBefore = token.balanceOf(token_whale)
    #eth to weth
    ethwrapping.deposit({'from': token_whale, 'value': "100 ether"})
    assert token.balanceOf(token_whale) > balanceBefore

    #START
    #weth to eth
    balanceBefore = token_whale.balance()
    ethwrapping.withdraw("100 ether", {'from': token_whale})
    assert token_whale.balance() > balanceBefore
    #eth to steth
    assert token_whale.balance()/1e18 > 100 
    assert steth.balanceOf(token_whale) == 0
    balanceBefore = steth.balanceOf(token_whale) == 0
    referal = accounts[3]
    #steth.submit(referal, {'from': token_whale, 'value': "100 ether"})
    StableSwapSTETH.exchange(0, 1, "100 ether", "99.5 ether", {'from': token_whale, 'value': "100 ether"})
    #StableSwapSTETH.exchange(0, 1, "100 ether", "100 ether", {'from': token_whale, 'value': "100 ether"})
    assert steth.balanceOf(token_whale) > balanceBefore

    #steth to wsteth
    assert wsteth.balanceOf(token_whale) == 0
    balanceBefore = wsteth.balanceOf(token_whale)
    steth.approve(wsteth, 2 ** 256 - 1, {'from': token_whale})
    wsteth.wrap("99 ether", {'from': token_whale})
    assert wsteth.balanceOf(token_whale) > balanceBefore
    #YAY WE GOT WSTETH

    #all the way back
    balanceBefore = token.balanceOf(token_whale)
    #wsteth --> steth
    wsteth.unwrap("80 ether", {'from': token_whale})
    #APPROVE STABLESWAP!!!!!
    #steth.approve()
    #steth --> eth
    steth.approve(StableSwapSTETH, 2 ** 256 - 1, {'from': token_whale})
    StableSwapSTETH.exchange(1, 0, "50 ether", "49.5 ether", {'from': token_whale})
    #eth --> weth
    ethwrapping.deposit({'from': token_whale, 'value': "50 ether"})
    assert token.balanceOf(token_whale) > balanceBefore
    #YAY it works, we're back to weth!

    #Check
    #StableSwapSTETH.get_dy(WETHID, STETHID, _amount);
    #stETH.submit{value: _amount}(referal);
    
    #StableSwapSTETH.exchange(STETHID, WETHID, _amount,slippageAllowance);


    #stETH.approve(address(StableSwapSTETH), type(uint256).max);

    #wsteth unwrapping and wrapping
    yieldBearingToken_whale = accounts.at("0xdaef20ea4708fcff06204a4fe9ddf41db056ba18", force= True)
    assert wsteth.balanceOf(yieldBearingToken_whale)/1e18 > 0
    steth.transfer(gov, steth.balanceOf(yieldBearingToken_whale), {'from': yieldBearingToken_whale})
    balanceBefore = steth.balanceOf(yieldBearingToken_whale)/1e18
    wsteth.unwrap("100 ether", {'from': yieldBearingToken_whale})
    assert steth.balanceOf(yieldBearingToken_whale)/1e18 > balanceBefore
    #now wrap back
    steth.approve(wsteth, 2 ** 256 - 1, {'from': yieldBearingToken_whale})
    steth.allowance(yieldBearingToken_whale, wsteth)/1e18 
    balanceBefore = wsteth.balanceOf(yieldBearingToken_whale)/1e18
    wsteth.wrap("2 ether", {'from': yieldBearingToken_whale})
    assert wsteth.balanceOf(yieldBearingToken_whale)/1e18 > balanceBefore


    
    #assert 0 == 1


def test_ilksource(strategy, gov, strategist, management, guardian, user, productionVault, ilk_want, ilk_yieldBearing, yieldBearingToken, token, gemJoinAdapter):
    #strategy.setCollateralizationRatio(200 * 1e18, {"from": prodgov})
    #assert strategy.collateralizationRatio() == 200 * 1e18

    ilkybaby = Contract("0x5a464C28D19848f44199D003BeF5ecc87d090F87")
    assert ilkybaby.gem(ilk_yieldBearing) == yieldBearingToken
    assert ilkybaby.gem(ilk_want) == token
    assert ilkybaby.join(ilk_yieldBearing) == gemJoinAdapter
    #assert strategy.t_getYieldBearingTokenAddress() == yieldBearingToken

