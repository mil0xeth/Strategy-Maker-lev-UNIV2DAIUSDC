from brownie import reverts


def test_set_max_loss_over_max_bps_should_revert(strategy, gov):
    maxBps = 10_000

    with reverts():
        strategy.setMaxLoss(maxBps + 1, {"from": gov})


def test_set_max_loss_to_max_bps_should_not_revert(strategy, gov):
    maxBps = 10_000
    strategy.setMaxLoss(maxBps, {"from": gov})
    assert strategy.maxLoss() == maxBps


def test_set_max_loss_under_max_bps_should_not_revert(strategy, gov):
    maxBps = 10_000
    strategy.setMaxLoss(maxBps - 1, {"from": gov})
    assert strategy.maxLoss() == maxBps - 1

def test_set_max_loss_acl(strategy, gov, strategist, management, guardian, user):
    strategy.setMaxLoss(10, {"from": gov})
    assert strategy.maxLoss() == 10

    strategy.setMaxLoss(11, {"from": management})
    assert strategy.maxLoss() == 11

    with reverts("!authorized"):
        strategy.setMaxLoss(12, {"from": strategist})

    with reverts("!authorized"):
        strategy.setMaxLoss(13, {"from": guardian})

    with reverts("!authorized"):
        strategy.setMaxLoss(14, {"from": user})