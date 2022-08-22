import brownie
from brownie import Contract
import pytest

def test_aauniswapV2_profit(
   router, unirouter, usdc, partnerToken, chain, dai, dai_whale, token_whale, vault, test_strategy, yieldBearing, token, amountBIGTIME, amountBIGTIME2, user2, user, gov, RELATIVE_APPROX, RELATIVE_APPROX_LOSSY
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

    priceBefore = test_strategy.getWantPerYieldBearing()
    strategyAssetsBefore = test_strategy.estimatedTotalAssets()
    vaultAssetsBefore = vault.totalAssets()
    strategyCollateralizationRatioBefore = test_strategy.getCurrentMakerVaultRatio()

    # Swap DAI for USDC to generate fees
    other_token = Contract('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48')    # usdc
    swap_amount = token.balanceOf(token_whale)*0.001
    token.approve(unirouter.address, swap_amount, {'from': token_whale})
    router.swapExactTokensForTokens(
        swap_amount,
        0,
        [token.address, other_token.address],
        token_whale.address,
        chain.time() + 1,
        {'from': token_whale}
    )
    chain.sleep(1)

    priceAfter = test_strategy.getWantPerYieldBearing()
    strategyAssetsAfter = test_strategy.estimatedTotalAssets()
    strategyCollateralizationRatioAfter = test_strategy.getCurrentMakerVaultRatio()

    assert strategyAssetsAfter-strategyAssetsBefore > 0

    #collect profits into vault
    test_strategy.harvest({"from": gov})
    vaultAssetsAfter = vault.totalAssets()

    assert vaultAssetsAfter > vaultAssetsBefore
    assert vault.strategies(test_strategy)["totalGain"] > 0

    #reinvest profits into strategy
    test_strategy.harvest({"from": gov})
    assert ( pytest.approx(test_strategy.getCurrentMakerVaultRatio(), rel=RELATIVE_APPROX) == test_strategy.collateralizationRatio())
    assert ( pytest.approx(test_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == vault.totalAssets())
