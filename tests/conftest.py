import pytest
from brownie import config, convert, interface, Contract
##################
#Notes: Reamining issues:
#0.: withdraw doesn't adjust coll ratio
#0.: why is uniswap still a problem? has correct settings
#1.: update form 0.6.12 solidity version to include uniswapv3?
#0.: _swap functions in MakerDaiDelegateLib access 
#0.: harvestTrigger NOT behaving as it should, usually True (solve with isCurrentBasefeeAcceptable OR minReportDelay) even while tendTrigger is true
#0.: ProfitLimitRatio / LossLimitRatio clear up: healthCheck set to profit 50%, loss 1%
#0.: test_debt_ratio has a healthcheck issue, even though the loss is not greater than 0.6%, requires losslimitratio of sometimes 70%, sometimes 90%. odd.
#Maybe because remaining loss is of the size of the entire position? Percentages then apply to the size of the positiion. How to fix?
#1.: MakerDaiDelegateLib functions decisions: external/internal etc.
#1.: OSMProxy for wstETH not implemented, still OSMProxy for ETH integrated
#4.: Remove SIZE OPTIMISATION
#5.: Referal: Functions, YieldBearing setFunction? Constructor, why initializeThis?
#6.: Why is the original _checkAllowance setting first allowance to zero, then to max? Why not immediately to max?
#8.: WANT token other than ETH or WETH need to enable chainlinkWantToETHPriceFeed
#9.: Disabled use of OSM Proxy for Want / Disabled use of OSM Proxy for yieldBearing (doesn't exist) 
#11.: maxSingleTrade implementation
#12.: Awaiting Flash in MakerDaiDelegateLib doAaveFlashloan ENABLE
#16.: awaitingFlash with AAVE Flashloan variable include
#################
#Decide on Strategy Contract
@pytest.fixture(autouse=True)
def StrategyChoice(Strategy):    
    choice = Strategy #Strategy = maker-eth-dai-delegator, NewStrategy = maker-wsteth-dai-lev 
    yield choice
@pytest.fixture(autouse=True)
def TestStrategyChoice(TestStrategy):    
    choice = TestStrategy #TestStrategy, NewTestStrategy
    yield choice
@pytest.fixture(autouse=True)
def MakerDaiDelegateClonerChoice(MakerDaiDelegateCloner):    
    choice = MakerDaiDelegateCloner 
    yield choice
#######################################################
#Decide on wantToken = token
@pytest.fixture(autouse=True)
def wantNr():    
    wantNr = 1 #Currently: WETH
    #0 = ETH,   1 = WETH,   2 = stETH,     3 = wstETH 
    yield wantNr
#######################################################
#Decide on yieldBearingToken = collateral Token on Money Market
@pytest.fixture(autouse=True)
def yieldBearingNr():    
    yieldBearingNr = 3 #Currently: WETH
    #0 = ETH,   1 = WETH,   2 = stETH,     3 = wstETH 
    yield yieldBearingNr
#######################################################
@pytest.fixture
def token(weth, steth, wsteth, wantNr):   
    #signifies want token given by wantNr
    token_address = [
    weth,   #0 = ETH
    weth,   #1 = WETH
    steth,  #2 = steth
    wsteth  #3 = wsteth
    ]
    yield token_address[wantNr]

@pytest.fixture
def yieldBearingToken(weth, steth, wsteth, yieldBearingNr):   
    #signifies want token given by wantNr
    yieldBearingToken_address = [
    weth,   #0 = ETH
    weth,   #1 = WETH
    steth,  #2 = steth
    wsteth  #3 = wsteth
    ]
    yield yieldBearingToken_address[yieldBearingNr]

@pytest.fixture
def borrow_token(dai):
    yield dai

@pytest.fixture
def borrow_whale(dai_whale):
    yield dai_whale
 
@pytest.fixture
def ethwrapping(interface):
    uniweth = interface.IWETH("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
    yield uniweth

@pytest.fixture
def steth(interface):
    contract = interface.ISteth("0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84")
    yield contract

@pytest.fixture
def wsteth(interface):
    contract = interface.IWstETH("0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0")
    yield contract

@pytest.fixture
def StableSwapSTETH(interface):
    contract = interface.ICurveFi("0xDC24316b9AE028F1497c275EB9192a3Ea0f67022")
    yield contract

#@pytest.fixture
#def StableSwapContract(interface):
#    contract = Contract("0xDC24316b9AE028F1497c275EB9192a3Ea0f67022")
#    yield contract


@pytest.fixture
def yvault(yvDAI):
    yield yvDAI

#chainlinkWantToETHPriceFeed
@pytest.fixture
def price_oracle_want_to_eth(wantNr):
    oracle_address = [
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",  #ETH/USD
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",  #ETH/USD
    "0xcfe54b5cd566ab89272946f602d76ea879cab4a8",  #stETH/USD
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"  #ETH/USD    no wsteth/USD available!
    ]
    yield interface.AggregatorInterface(oracle_address[wantNr])

@pytest.fixture
def price_oracle_yieldBearing_to_eth(yieldBearingNr):
    oracle_address = [
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",  #ETH/USD
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",  #ETH/USD
    "0xcfe54b5cd566ab89272946f602d76ea879cab4a8",  #stETH/USD
    "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"  #ETH/USD    no wsteth/USD available!
    ]
    yield interface.AggregatorInterface(oracle_address[yieldBearingNr])


#############################################################

@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" #WETH
    yield Contract(token_address)   

#@pytest.fixture
#def steth():
#    token_address = "0xae7ab96520de3a18e5e111b5eaab095312d7fe84" #stETH
#    yield Contract(token_address)

#@pytest.fixture
#def wsteth():
#    token_address = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"  # wstETH
#    yield Contract(token_address)

@pytest.fixture
def dai():
    dai_address = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    yield Contract(dai_address)

#@pytest.fixture
#def steth_whale(accounts):
#    yield accounts.at("0x2faf487a4414fe77e2327f0bf4ae2a264a776ad2") 

#@pytest.fixture
#def wsteth_whale(accounts):
#    yield accounts.at("0x62e41b1185023bcc14a465d350e1dde341557925") 


@pytest.fixture
def token_whale(accounts, wantNr):
    #eth_whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    eth_whale = accounts.at("0xda9dfa130df4de4673b89022ee50ff26f6ea73cf", force=True)
    token_whale_address = [
    "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",   #0 = ETH
    "0xe78388b4ce79068e89bf8aa7f218ef6b9ab0e9d0",   #1 = WETH  0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0x57757e3d981446d585af0d9ae4d7df6d64647806  
    "0x2faf487a4414fe77e2327f0bf4ae2a264a776ad2",  #2 = steth
    "0x62e41b1185023bcc14a465d350e1dde341557925"  #3 = wsteth
    ]
    token_whale_account = accounts.at(token_whale_address[wantNr], force=True) 
    eth_whale.transfer(token_whale_account, "100000 ether")
    yield token_whale_account

@pytest.fixture
def token_whale_BIG(accounts, wantNr, ethwrapping):
    eth_whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    token_whale_address = [
    "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",   #0 = ETH
    "0xe78388b4ce79068e89bf8aa7f218ef6b9ab0e9d0",   #1 = WETH  0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0x57757e3d981446d585af0d9ae4d7df6d64647806  
    "0x2faf487a4414fe77e2327f0bf4ae2a264a776ad2",  #2 = steth
    "0x62e41b1185023bcc14a465d350e1dde341557925"  #3 = wsteth
    ]
    token_whale_account = accounts.at(token_whale_address[wantNr], force=True) 
    eth_whale.transfer(token_whale_account, eth_whale.balance()*0.95)
    ethwrapping.deposit({'from': token_whale_account, 'value': token_whale_account.balance()*0.95})
    yield token_whale_account


@pytest.fixture
def yieldBearingToken_whale(accounts, yieldBearingNr):
    eth_whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    yieldBearingToken_whale_address = [
    "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",   #0 = ETH
    "0xe78388b4ce79068e89bf8aa7f218ef6b9ab0e9d0",   #1 = WETH  0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0x57757e3d981446d585af0d9ae4d7df6d64647806  
    "0x2faf487a4414fe77e2327f0bf4ae2a264a776ad2",  #2 = steth
    "0xdaef20ea4708fcff06204a4fe9ddf41db056ba18"  #3 = wsteth
    ]
    yieldBearingToken_whale_account = accounts.at(yieldBearingToken_whale_address[yieldBearingNr], force=True) 
    eth_whale.transfer(yieldBearingToken_whale_account, "100000 ether")
    yield yieldBearingToken_whale_account

@pytest.fixture
def weth_amount(user, weth):
    weth_amount = 10 ** weth.decimals()
    user.transfer(weth, weth_amount)
    yield weth_amount

@pytest.fixture
def weth_whale(accounts):
    yield accounts.at("0x57757e3d981446d585af0d9ae4d7df6d64647806", force=True)

@pytest.fixture
def dai_whale(accounts):
    yield accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)

@pytest.fixture
def yvDAI():
    vault_address = "0xdA816459F1AB5631232FE5e97a05BBBb94970c95"
    yield Contract(vault_address)

@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass

@pytest.fixture(autouse=True)
def lib(gov, MakerDaiDelegateLib):
    yield MakerDaiDelegateLib.deploy({"from": gov})

@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)

@pytest.fixture
def user(accounts):
    yield accounts[0]

@pytest.fixture
def user2(accounts):
    yield accounts[0]

@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts.at("0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7", force=True)

@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def router(unirouter, sushirouter):
    yield unirouter

@pytest.fixture
def sushirouter():
    sushiswap_router = interface.ISwap("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")
    yield sushiswap_router

@pytest.fixture
def unirouter():
    uniswap_router = interface.ISwap("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")
    yield uniswap_router


@pytest.fixture
def amount(accounts, token, user, token_whale):
    amount = 50 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = token_whale
    #reserve = accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount

@pytest.fixture
def amount2(accounts, token, user2, token_whale):
    amount = 50 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    #reserve = accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True)
    reserve = token_whale
    token.transfer(user2, amount, {"from": reserve})
    yield amount


@pytest.fixture
def amountBIGTIME(accounts, token, user, token_whale):
    #amount = 20000 * 10 ** token.decimals()
    amount = 1000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    #reserve = accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True)
    reserve = token_whale
    token.transfer(user, amount, {"from": reserve})
    yield amount

@pytest.fixture
def amountBIGTIME2(accounts, token, user2, token_whale):
    #amount = 6000 * 10 ** token.decimals()
    amount = 600 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    #reserve = accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True)
    reserve = token_whale
    token.transfer(user2, amount, {"from": reserve})
    yield amount


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault
    
@pytest.fixture
def productionVault(wantNr):
    vault_address = [
    "",  #ETH/USD
    "0xa258C4606Ca8206D8aA700cE2143D7db854D168c",  #yvWETH
    "",  #yvstETH
    ""  #yvwstETH
    ]
    yield Contract(vault_address[wantNr])

@pytest.fixture
def new_dai_yvault(pm, gov, rewards, guardian, management, dai):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(dai, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault

@pytest.fixture
def new_full_dai_yvault(pm, gov, rewards, guardian, management, dai, new_dai_yvault, dai_whale):
    yvDAI = new_dai_yvault
    dai.approve(yvDAI.address, "500_000 ether", {"from": dai_whale})
    yvDAI.deposit("500_000 ether", {"from": dai_whale})
    yield yvDAI


@pytest.fixture
def osmProxy_want():
    # Allow the strategy to query the OSM proxy
    osm = Contract("0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1")   # Points to ETH/USD
    # osm = interface.IOSMedianizer("0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1")
    yield osm

@pytest.fixture
def osmProxy_yieldBearing():
    # Allow the strategy to query the OSM proxy
    osm = Contract("0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1")
    #osm = interface.IOSMedianizer("0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1")
    yield osm

#@pytest.fixture
#def gemJoinAdapter():
#    gemJoin = Contract("0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E")  # WETH-C
#    yield gemJoin
    
#This is the collateral adapter, so yieldbearing token, not want token if want != yieldBearing
@pytest.fixture
def gemJoinAdapter(yieldBearingNr):
    gemJoin = [
    "0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E",   #0 = ETH     Doesn't exist ---> WETH-C
    "0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E",   #1 = WETH    is   WETH-C
    "0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2",  #Doesn't exist yet 2 = steth ---> = wsteth  is wstETH-A
    "0x10CD5fbe1b404B7E19Ef964B63939907bdaf42E2"  #3 = wsteth is wstETH-A
    ]
    yield Contract(gemJoin[yieldBearingNr])


@pytest.fixture
def healthCheck(gov):
    healthCheck = Contract("0xDDCea799fF1699e98EDF118e0629A974Df7DF012")
    healthCheck.setProfitLimitRatio(1000, {"from": gov})  #default 100, # 1%
    healthCheck.setlossLimitRatio(100, {"from": gov})  #default 1 # 0.01%
    #healthCheck.setProfitLimitRatio(5000, {"from": gov})  #default 100, # 1%
    #healthCheck.setlossLimitRatio(100, {"from": gov})  #default 1 # 0.01%
    yield healthCheck

@pytest.fixture
def custom_osm(TestCustomOSM, gov):
    yield TestCustomOSM.deploy({"from": gov})

#@pytest.fixture
#def custom_osm(TestCustomOSM, gov):
#    yield TestCustomOSM.deploy({"from": gov})

@pytest.fixture
def strategy(vault, StrategyChoice, gov, osmProxy_want, osmProxy_yieldBearing, cloner, healthCheck):
    strategy = StrategyChoice.at(cloner.original())
    #healthcheck = healthCheck
    #strategy.setRetainDebtFloorBool(False, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    # set a high acceptable max base fee to avoid changing test behavior
    #strategy.setMaxAcceptableBaseFee(1500 * 1e9, {"from": gov})

    vault.addStrategy(strategy, 
        10_000, #debtRatio 
        0,  #minDebtPerHarvest
        2 ** 256 - 1,  #maxDebtPerHarvest
        1_000, #performanceFee = 10% = 1_000
        #5_000, #= 50%, profitLimitRatio, default = 100 = 1%
        #2_500, #= 25% lossLimitRatio, default = 1 == 0.01%  
        {"from": gov}) 

    # Allow the strategy to query the OSM proxy
    #osmProxy_want.setAuthorized(strategy, {"from": gov})
    #osmProxy_yieldBearing.setAuthorized(strategy, {"from": gov})
    yield strategy

@pytest.fixture
def test_strategy(
    TestStrategyChoice,
    strategist,
    vault,
    yvault,
    token,
    yieldBearingToken,
    gemJoinAdapter,
    osmProxy_want,
    osmProxy_yieldBearing,
    #price_oracle_want_to_eth,
    gov, ilk_yieldBearing, ilk_want, healthCheck
):
    strategy = strategist.deploy(
        TestStrategyChoice,
        vault,
        yvault,
        "Strategy-Maker-lev-wstETH",
        #ilk_want,
        #ilk_yieldBearing,
        #gemJoinAdapter,
      #  osmProxy_want,
      #  osmProxy_yieldBearing,
      #  price_oracle_want_to_eth
    )
    #strategy.setRetainDebtFloorBool(False, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})

    # set a high acceptable max base fee to avoid changing test behavior
    # strategy.setMaxAcceptableBaseFee(1500 * 1e9, {"from": gov})

    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    # Allow the strategy to query the OSM proxy
    #osmProxy_want.setAuthorized(strategy, {"from": gov})
    #osmProxy_yieldBearing.setAuthorized(strategy, {"from": gov})
    yield strategy


#@pytest.fixture
#def ilk_WETH_C():
#    ilk = "0x4554482d43000000000000000000000000000000000000000000000000000000"  # WETHC
#    yield ilk

#@pytest.fixture
#def ilk_wstETH():
#    ilk = "0x5753544554482d41000000000000000000000000000000000000000000000000"  # wstETH
#    yield ilk

@pytest.fixture
def ilk_want(wantNr):
    ilk_hashes = [
    "0x4554482d43000000000000000000000000000000000000000000000000000000",   #0 = WETH
    "0x4554482d43000000000000000000000000000000000000000000000000000000",   #1 = WETH
    "0x5753544554482d41000000000000000000000000000000000000000000000000",  #2 = wsteth
    "0x5753544554482d41000000000000000000000000000000000000000000000000"  #3 = wsteth
    ]
    yield ilk_hashes[wantNr]


@pytest.fixture
def ilk_yieldBearing(yieldBearingNr):
    ilk_hashes = [
    "0x4554482d43000000000000000000000000000000000000000000000000000000",   #0 = WETH
    "0x4554482d43000000000000000000000000000000000000000000000000000000",   #1 = WETH
    "0x5753544554482d41000000000000000000000000000000000000000000000000",  #2 = wsteth
    "0x5753544554482d41000000000000000000000000000000000000000000000000"  #3 = wsteth
    ]
    yield ilk_hashes[yieldBearingNr]




@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5

@pytest.fixture(scope="session")
def RELATIVE_APPROX_LOSSY():
    yield 1e-2

@pytest.fixture(scope="session")
def RELATIVE_APPROX_ROUGH():
    yield 1e-1

# Obtaining the bytes32 ilk (verify its validity before using)
# >>> ilk = ""
# >>> for i in "YFI-A":
# ...   ilk += hex(ord(i)).replace("0x","")
# ...
# >>> ilk += "0"*(64-len(ilk))
# >>>
# >>> ilk
# '5946492d41000000000000000000000000000000000000000000000000000000'

@pytest.fixture
def cloner(
    strategist,
    vault,
    yvault,
    token,
    yieldBearingToken,
    gemJoinAdapter,
    osmProxy_want,
    osmProxy_yieldBearing,
   # price_oracle_want_to_eth,
    MakerDaiDelegateClonerChoice,
    ilk_yieldBearing, ilk_want
):
    cloner = strategist.deploy(
        MakerDaiDelegateClonerChoice,
        vault,
        yvault,
        "Strategy-Maker-lev-wstETH",
        #ilk_want,
        #ilk_yieldBearing,
        #gemJoinAdapter,
     #   osmProxy_want,
     #   osmProxy_yieldBearing,
     #   price_oracle_want_to_eth,
    )
    yield cloner
