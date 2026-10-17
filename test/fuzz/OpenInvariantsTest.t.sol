/*
//SPDX-License-Identifier: MIT

// what are the invariants
// 1. total value of dsc should be less than the total number of our collateral
//2. getter functions should never revert

pragma solidity ^0.8.18;
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get the value of all the collateral in the contract and compare it to all the debt
           uint256 totalSupply = dsc.totalSupply();
           uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
           uint256 totalWbtcDeposited =  IERC20(wbtc).balanceOf(address(dsce));

           uint256 wethValue =  dsce.getUsdValue(weth, totalWethDeposited);
           uint256 wbtcValue =  dsce.getUsdValue(wbtc, totalWbtcDeposited);

          console.log("weth value :",  wethValue);
          console.log("wbtc value :",  wethValue);
          console.log("total supply :",  totalSupply);

           assert(wethValue + wbtcValue >= totalSupply);

        }
}

*/ 