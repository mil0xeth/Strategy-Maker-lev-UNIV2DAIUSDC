// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface GUniPool is IERC20 {

    /// @notice mint fungible G-UNI tokens, fractional shares of a Uniswap V3 position
    /// @dev to compute the amouint of tokens necessary to mint `mintAmount` see getMintAmounts
    /// @param mintAmount The number of G-UNI tokens to mint
    /// @param receiver The account to receive the minted tokens
    /// @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
    /// @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
    /// @return liquidityMinted amount of liquidity added to the underlying Uniswap V3 position
    // solhint-disable-next-line function-max-lines, code-complexity
    function mint(uint256 mintAmount, address receiver)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityMinted
        );

    /// @notice burn G-UNI tokens (fractional shares of a Uniswap V3 position) and receive tokens
    /// @param burnAmount The number of G-UNI tokens to burn
    /// @param receiver The account to receive the underlying amounts of token0 and token1
    /// @return amount0 amount of token0 transferred to receiver for burning `burnAmount`
    /// @return amount1 amount of token1 transferred to receiver for burning `burnAmount`
    /// @return liquidityBurned amount of liquidity removed from the underlying Uniswap V3 position
    // solhint-disable-next-line function-max-lines
    function burn(uint256 burnAmount, address receiver)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityBurned
        );

    // View functions

    /// @notice compute maximum G-UNI tokens that can be minted from `amount0Max` and `amount1Max`
    /// @param amount0Max The maximum amount of token0 to forward on mint
    /// @param amount0Max The maximum amount of token1 to forward on mint
    /// @return amount0 actual amount of token0 to forward when minting `mintAmount`
    /// @return amount1 actual amount of token1 to forward when minting `mintAmount`
    /// @return mintAmount maximum number of G-UNI tokens to mint
    function getMintAmounts(uint256 amount0Max, uint256 amount1Max)
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 mintAmount
        );

    /// @notice compute total underlying holdings of the G-UNI token supply
    /// includes current liquidity invested in uniswap position, current fees earned
    /// and any uninvested leftover (but does not include manager or gelato fees accrued)
    /// @return amount0Current current total underlying balance of token0
    /// @return amount1Current current total underlying balance of token1
    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0Current, uint256 amount1Current);

}



