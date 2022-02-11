def test_tend_trigger_conditions(
    vault, strategy, token, token_whale, amount, user, gov
):
    # Initial ratio is 0 because there is no collateral locked
    assert strategy.tendTrigger(1) == False
    # Deposit to the vault and send funds through the strategy
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    orig_target = strategy.collateralizationRatio()
    rebalance_tolerance = strategy.rebalanceTolerance()

    # Make sure we are in equilibrium
    assert strategy.tendTrigger(1) == False

    # Going under the rebalancing band should need to adjust position
    # regardless of the max acceptable base fee
    strategy.setCollateralizationRatio(
        orig_target + rebalance_tolerance * 1.001, {"from": gov}
    )

    strategy.setMaxAcceptableBaseFee(0, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == True

    strategy.setMaxAcceptableBaseFee(1001 * 1e9, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == True

    # Going over the target ratio but inside rebalancing band should not adjust position
    strategy.setCollateralizationRatio(
        orig_target + rebalance_tolerance * 0.999, {"from": gov}
    )
    assert strategy.tendTrigger(1) == False

    # Going over the rebalancing band should need to adjust position
    # but only if block's base fee is deemed to be acceptable
    strategy.setCollateralizationRatio(
        orig_target - rebalance_tolerance * 1.001, {"from": gov}
    )

    # Max acceptable base fee is set to 1000 gwei for testing, so go just
    # 1 gwei above and 1 gwei below to cover both sides
    strategy.setMaxAcceptableBaseFee(1001 * 1e9, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == True

    strategy.setMaxAcceptableBaseFee(1000 * 1e9, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == True

    strategy.setMaxAcceptableBaseFee(999 * 1e9, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == False

    # Going over the target ratio but inside rebalancing band should not adjust position
    strategy.setCollateralizationRatio(
        orig_target - rebalance_tolerance * 0.999, {"from": gov}
    )
    strategy.setMaxAcceptableBaseFee(1001 * 1e9, {"from": strategy.strategist()})
    assert strategy.tendTrigger(1) == False



    #token.approve(vault.address, 2 ** 256 - 1, {"from": token_whale})
    #vault.deposit(Wei("10_000 ether"), {"from": token_whale})

    # Send the funds through the strategy to invest
    #chain.sleep(1)
    #strategy.harvest({"from": gov})
