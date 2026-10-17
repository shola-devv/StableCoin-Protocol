//SPDX-License-Iidentifier: MIT

pragma solidity ^0.8.18;
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

 

contract Handler is Test {

    //DeployDSC deployer;
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    //HelperConfig config;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;


   constructor (DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
    dsce = _dscEngine;
    dsc = _dsc;

      address[] memory collateralTokens = dsce.getCollateralTokens();
      weth = ERC20Mock(collateralTokens[0]);
      wbtc = ERC20Mock(collateralTokens[1]);

   }

   //redeem collateral
 function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
   //  dsce.depositCollateral(collateral, amountCollateral);
   ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
   amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
   vm.startPrank(msg.sender);
   collateral.mint(msg.sender, amountCollateral);
   collateral.approve(address(dsce), amountCollateral);
   dsce.depositCollateral(address(collateral), amountCollateral);
   vm.stopPrank();
 }

function _getCollateralFromSeed(uint256 collateralSeed ) private view returns(ERC20Mock) {
   if (collateralSeed % 2 == 0){
    return weth;
   }
   return wbtc;
}
}
