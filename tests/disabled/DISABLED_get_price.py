import pytest

from brownie import interface, reverts, Wei


def test_osm_reverts_should_use_spot(test_strategy, custom_osm, lib, ilk_yieldBearing):
    test_strategy.setWantAndYieldBearingUSDOSMProxy(custom_osm,custom_osm)
    osm = interface.IOSMedianizer(test_strategy.yieldBearingToUSDOSMProxy())

    custom_osm.setCurrentPrice(0, True)
    custom_osm.setFuturePrice(0, True)

    with reverts():
        osm.read()

    with reverts():
        osm.foresight()

    price = test_strategy._getYieldBearingPrice()

    assert price > 0
    assert price == lib.getSpotPrice(ilk_yieldBearing)


def test_current_osm_reverts_should_use_min_future_and_spot(
    test_strategy, custom_osm, lib, RELATIVE_APPROX, ilk_yieldBearing
):
    test_strategy.setWantAndYieldBearingUSDOSMProxy(custom_osm,custom_osm)
    osm = interface.IOSMedianizer(test_strategy.yieldBearingToUSDOSMProxy())

    spot = lib.getSpotPrice(ilk_yieldBearing)

    custom_osm.setCurrentPrice(0, True)
    with reverts():
        osm.read()

    custom_osm.setFuturePrice(spot - 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot - 1e18
    assert (
        pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX)
        == osm.foresight()[0]
    )

    custom_osm.setFuturePrice(spot + 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot
    assert test_strategy._getYieldBearingPrice() > 0


def test_future_osm_reverts_should_use_min_future_and_spot(
    test_strategy, custom_osm, lib, RELATIVE_APPROX, ilk_yieldBearing
):
    test_strategy.setWantAndYieldBearingUSDOSMProxy(custom_osm,custom_osm)
    osm = interface.IOSMedianizer(test_strategy.yieldBearingToUSDOSMProxy())

    spot = lib.getSpotPrice(ilk_yieldBearing)

    custom_osm.setFuturePrice(0, True)
    with reverts():
        osm.foresight()

    custom_osm.setCurrentPrice(spot - 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot - 1e18
    assert (
        pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == osm.read()[0]
    )

    custom_osm.setCurrentPrice(spot + 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot
    assert test_strategy._getYieldBearingPrice() > 0


def test_get_price_should_return_min_price(
    test_strategy, custom_osm, lib, RELATIVE_APPROX, ilk_yieldBearing
):
    test_strategy.setWantAndYieldBearingUSDOSMProxy(custom_osm,custom_osm)
    osm = interface.IOSMedianizer(test_strategy.yieldBearingToUSDOSMProxy())

    spot = lib.getSpotPrice(ilk_yieldBearing)

    custom_osm.setFuturePrice(spot + 1e18, False)
    custom_osm.setCurrentPrice(spot + 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot

    custom_osm.setFuturePrice(spot - 1e18, False)
    custom_osm.setCurrentPrice(spot + 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot - 1e18
    assert (
        pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX)
        == osm.foresight()[0]
    )

    custom_osm.setFuturePrice(spot + 1e18, False)
    custom_osm.setCurrentPrice(spot - 1e18, False)
    assert pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == spot - 1e18
    assert (
        pytest.approx(test_strategy._getYieldBearingPrice(), rel=RELATIVE_APPROX) == osm.read()[0]
    )
