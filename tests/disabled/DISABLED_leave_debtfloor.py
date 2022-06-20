def test_set_leave_debt_behind_acl(
    strategy, gov, strategist, management, guardian, user
):
    strategy.setRetainDebtFloorBool(True, {"from": gov})
    assert strategy.debtFloor() == True

    strategy.setRetainDebtFloorBool(False, {"from": strategist})
    assert strategy.debtFloor() == False

    strategy.setRetainDebtFloorBool(True, {"from": management})
    assert strategy.debtFloor() == True

    strategy.setRetainDebtFloorBool(False, {"from": guardian})
    assert strategy.debtFloor() == False

    with reverts("!authorized"):
        strategy.setRetainDebtFloorBool(True, {"from": user})