import pytest

from brownie import Contract, reverts


def test_migration(
    chain,
    wsteth,
    token,
    vault,
    yvault,
    strategy,
    strategist,
    amount,
    Strategy,
    gov,
    user,
    cloner,
    ilk_want,
    ilk_yieldBearing,
    gemJoinAdapter,
    RELATIVE_APPROX_LOSSY,
    osmProxy_want,
    osmProxy_yieldBearing
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY) == amount

    # migrate to a new strategy
    new_strategy = Strategy.at(
        cloner.cloneMakerDaiDelegate(
            vault,
            strategist,
            strategist,
            strategist,
            yvault,
            "name",
            #ilk_want,
            #ilk_yieldBearing,
            #gemJoinAdapter,
            #strategy.wantToUSDOSMProxy(),
            #strategy.yieldBearingToUSDOSMProxy(),
            #strategy.chainlinkWantToETHPriceFeed(),
        ).return_value
    )

    vault.migrateStrategy(strategy, new_strategy, {"from": gov})

    # Allow the new strategy to query the OSM proxy
    #osmProxy_want = Contract(strategy.wantToUSDOSMProxy())
    #osmProxy_yieldBearing = Contract(strategy.yieldBearingToUSDOSMProxy())
    #osmProxy_want.setAuthorized(new_strategy, {"from": gov})
    #osmProxy_yieldBearing.setAuthorized(new_strategy, {"from": gov})

    orig_cdp_id = strategy.cdpId()
    new_strategy.shiftToCdp(orig_cdp_id, {"from": gov})
    new_strategy.harvest({"from": gov})

    assert pytest.approx(wsteth.getStETHByWstETH(new_strategy.balanceOfMakerVault()), rel=RELATIVE_APPROX_LOSSY) == amount
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY)
        == amount
    )
    assert new_strategy.cdpId() == orig_cdp_id
    assert vault.strategies(new_strategy).dict()["totalDebt"] == amount

    # Old strategy should have relinquished ownership of the CDP
    with reverts("cdp-not-allowed"):
        strategy.shiftToCdp(orig_cdp_id, {"from": gov})


def test_yvault_migration(
    chain,
    token,
    vault,
    strategy,
    amount,
    user,
    gov,
    yvault,
    new_dai_yvault,
    dai,
    RELATIVE_APPROX_LOSSY,
):
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY) == amount

    balanceBefore = yvault.balanceOf(strategy) * yvault.pricePerShare() / 1e18

    strategy.migrateToNewDaiYVault(new_dai_yvault, {"from": gov})

    assert yvault.balanceOf(strategy) == 0
    assert dai.allowance(strategy, yvault) == 0
    assert dai.allowance(strategy, new_dai_yvault) == 2 ** 256 - 1
    assert (pytest.approx(new_dai_yvault.balanceOf(strategy) * new_dai_yvault.pricePerShare() / 1e18, rel=RELATIVE_APPROX_LOSSY,) == balanceBefore)
    #assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_LOSSY) == amount


def test_yvault_migration_with_no_assets(
    token, vault, strategy, amount, user, gov, yvault, new_dai_yvault,
):

    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    assert strategy.estimatedTotalAssets() == 0
    strategy.migrateToNewDaiYVault(new_dai_yvault, {"from": gov})

    strategy.harvest({"from": gov})

    assert new_dai_yvault.balanceOf(strategy) > 0
    assert yvault.balanceOf(strategy) == 0
