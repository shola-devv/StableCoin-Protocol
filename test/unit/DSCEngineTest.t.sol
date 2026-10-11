// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }


//////////////////////////////
//////constructor test///////
/////////////////////////////


address[] public tokenAddresses;
address[] public priceFeedAddresses;

function testRevertIfTokenLengthDosentMatchPriceFeeds() public {

tokenAddresses.push(weth);
priceFeedAddresses.push(ethUsdPriceFeed);
priceFeedAddresses.push(btcUsdPriceFeed);

vm.expectRevert(DSCEngine, DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
  new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));


}


function testGETTokenAmountFromUsd() public {
       uint256 usdAmount = 100 ether;
       uint256 expectedWeth = 0.5 ether;
       uint256 actualWeth = dsc.getTokenAmountFromUsd(weth, usdAmount);
       assertEq(expectedWeth, actualWeth);

}



 //////////////////////////////
 //////Test pricefeeds/////
/////////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    //////////////////////////////
    //////Deposit collateral/////
    /////////////////////////////

    function testIfCollateralIsZero() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

function testREvertWithUnapprovedCollateral()  public {
       ERC20Mock  ranToken = new ERC20Mock("RAN","RAN", USER, AMOUNT_COLLATERAL);
       vm.startPrank(USER);
       vm.expertRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
       dsce.depositCoLlateral(address(ranToken), AMOUNT_COLLATERAL);

        
}



















}

/*
 (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
 assertNotEq(wethUsdPriceFeed, address(0));
        assertNotEq(wbtcUsdPriceFeed, address(0));
        assertNotEq(weth, address(0));
        assertNotEq(wbtc, address(0));
        assertGt(dsce.getUsdValue(weth, 1e18), 0);
*/