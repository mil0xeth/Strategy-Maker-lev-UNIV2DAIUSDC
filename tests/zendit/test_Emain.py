import pytest
from brownie import reverts, chain, Contract, Wei, history, ZERO_ADDRESS
 

def test_prod(accounts, ethwrapping, StableSwapSTETH, steth, wsteth, Strategy, token, token_whale, MakerDaiDelegateClonerChoice, strategist, yieldBearingToken, productionVault, yvault, ilk_want, ilk_yieldBearing, gemJoinAdapter, osmProxy_want, osmProxy_yieldBearing, price_oracle_want_to_eth):
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
        osmProxy_want,
        osmProxy_yieldBearing,
    #    price_oracle_want_to_eth
    )

    original_strategy_address = history[-1].events["Deployed"]["original"]
    strategy = Strategy.at(original_strategy_address)

    # White-list the strategy in the OSM!
    osmProxy_want.setAuthorized(strategy, {"from": gov})
    osmProxy_yieldBearing.setAuthorized(strategy, {"from": gov})

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
    wsteth.wrap("100 ether", {'from': token_whale})
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

