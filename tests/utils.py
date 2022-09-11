
ether = 10 ** 18

def print_state(message, vault, strategy, user, token, partnerToken, yieldBearing):
    print('-' * 5, message, '-' * 5)
    print('DAI Balances')
    print('User :', token.balanceOf(user.address) / ether)
    print('Vault:', token.balanceOf(vault.address) / ether)
    print('Strat:', token.balanceOf(strategy.address) / ether)
    print('\n')

    print('USDC Balances')
    print('User :', partnerToken.balanceOf(user.address) / 10 ** 6)
    print('Vault:', partnerToken.balanceOf(vault.address) / 10 ** 6)
    print('Strat:', partnerToken.balanceOf(strategy.address) / 10 ** 6)
    print('\n')

    print('Vault')
    print('User shares:', vault.balanceOf(user.address) / ether)
    print('maxAvailableShares', vault.maxAvailableShares() / ether)
    print('pricePerShare', vault.pricePerShare() / ether)
    print('\n')

    print('Strategy')
    (
        performanceFee,
        activation,
        debtRatio,
        minDebtPerHarvest,
        maxDebtPerHarvest,
        lastReport,
        totalDebt,
        totalGain,
        totalLoss
    ) = vault.strategies(strategy.address)
    print('totalDebt', totalDebt / ether)
    print('totalGain', totalGain / ether)
    print('totalLoss', totalLoss / ether)
    print('lastReport', lastReport)
    print('estimatedTotalAssets', strategy.estimatedTotalAssets() / ether)
    print('\n')

    print('Strategy Position on Maker')
    print('getUnitLpTokenValue', strategy.getUnitLpTokenValue() / ether)
    (collatBalance, debtBalance) = strategy.getCurrentPosition()
    print('getCurrentPosition', collatBalance / ether, debtBalance / ether)
    (collatValue, debtValue) = strategy.getCurrentPositionValues()
    print('getCurrentPositionValues', collatValue / ether, debtValue / ether)
    print('getCurrentCollatRatio', strategy.getCurrentCollatRatio() / ether)
    print('\n')

    print('DAIUSDC Pool')
    (dai_reserve, usdc_reserve) = yieldBearing.getReserves()
    print('Dai  reserve', dai_reserve / ether)
    print('Dai  balance', token.balanceOf(user.address) / ether)
    print('usdc reserve', usdc_reserve / 10 ** 6)
    print('usdc balance', partnerToken.balanceOf(user.address) / 10 ** 6)
    print('\n')

    print('DAIUSDC balances')    
    print('User :', yieldBearing.balanceOf(user.address) / ether)
    print('Vault:', yieldBearing.balanceOf(vault.address) / ether)
    print('Strat:', yieldBearing.balanceOf(strategy.address) / ether)
    print('Maker:', yieldBearing.balanceOf(vault.address) / ether)
    print('\n')