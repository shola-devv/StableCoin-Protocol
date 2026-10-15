// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant LIQUIDATOR_COLLATERAL = 20 ether;
    uint256 public constant AMOUNT_DSC_TO_BURN = 6 ether;

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(
        address indexed redeemedFrom, address indexed addressRedeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, LIQUIDATOR_COLLATERAL);
    }

    // Verifies constructor input validation. Scope: token/feed array length mismatch.
    function testRevertIfTokenLengthDosentMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        priceFeedAddresses[1] = btcUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Verifies USD-to-collateral conversion. Scope: ETH price feed precision.
    function testGetTokenAmountFromUsd() public view {
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(actualWeth, 0.05 ether);
    }

    // Verifies collateral-to-USD conversion. Scope: ETH amount and feed precision.
    function testGetUsdValue() public view {
        uint256 actualUsd = dsce.getUsdValue(weth, 15 ether);
        assertEq(actualUsd, 30_000 ether);
    }

    // Verifies account health before borrowing. Scope: a zero-debt account has the maximum health factor.
    function testHealthFactorIsMaxWhenAccountHasNoDebt() public {
        vm.prank(USER);
        assertEq(dsce.getHealthFactor(), type(uint256).max);
    }

    // Verifies zero-value deposits are rejected. Scope: depositCollateral's nonzero modifier.
    function testIfCollateralIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(USER);
        dsce.depositCollateral(weth, 0);
    }

    // Verifies only configured collateral is accepted. Scope: depositCollateral's token allowlist.
    function testREvertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(USER, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        vm.prank(USER);
        dsce.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
    }

    // Verifies deposits emit the event and update account collateral value. Scope: successful WETH deposit.
    function testCanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true, address(dsce));
        emit collateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 20_000 ether);
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
    }

    // Verifies zero-value redemptions are rejected. Scope: redeemCollateral's nonzero modifier.
    function testRedeemCollateralRevertsForZeroAmount() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(USER);
        dsce.redeemCollateral(weth, 0);
    }

    // Verifies collateral redemption transfers tokens and emits the expected event. Scope: a debt-free account.
    function testRedeemCollateral() public {
        _depositCollateral(USER, AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true, address(dsce));
        emit collateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);

        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE);
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(collateralValueInUsd, 0);
    }

    // Verifies redemptions cannot make a borrower undercollateralized. Scope: health-factor rollback.
    function testRedeemCollateralRevertsIfHealthFactorBreaks() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, 10_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine_breaksHealthFactor.selector, 0.9 ether)
        );
        vm.prank(USER);
        dsce.redeemCollateral(weth, 1 ether);

        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 10_000 ether);
    }

    // Verifies redemption cannot exceed deposited collateral. Scope: collateral accounting underflow.
    function testRedeemCollateralRevertsWhenAmountExceedsDeposit() public {
        _depositCollateral(USER, AMOUNT_COLLATERAL);

        vm.expectRevert();
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
    }

    // Verifies zero-value mint requests are rejected. Scope: mintDSC's nonzero modifier.
    function testMintDscRevertsForZeroAmount() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(USER);
        dsce.mintDSC(0);
    }

    // Verifies minting is capped by collateral value. Scope: mintDSC health-factor validation.
    function testMintDscRevertsIfHealthFactorBreaks() public {
        _depositCollateral(USER, AMOUNT_COLLATERAL);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine_breaksHealthFactor.selector, 999900009999000099
            )
        );
        vm.prank(USER);
        dsce.mintDSC(10_001 ether);

        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 0);
    }

    // Verifies valid minting updates both engine debt and DSC supply. Scope: safe mint from deposited WETH.
    function testMintDscUpdatesDebtAndBalance() public {
        _depositCollateral(USER, AMOUNT_COLLATERAL);

        vm.prank(USER);
        dsce.mintDSC(1_000 ether);

        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 1_000 ether);
        assertEq(dsc.balanceOf(USER), 1_000 ether);
    }

    // Verifies burnDSC rejects zero-value burns. Scope: burnDSC's nonzero modifier.
    function testBurnDscRevertsForZeroAmount() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(USER);
        dsce.burnDSC(0);
    }

    // Verifies a burn reduces recorded debt when the engine holds DSC to burn. Scope: _burnDsc success path.
    function testBurnDscReducesDebt() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, 1_000 ether);
        _fundEngineForBurn(400 ether);

        vm.startPrank(USER);
        dsc.approve(address(dsce), 400 ether);
        dsce.burnDSC(400 ether);
        vm.stopPrank();

        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 600 ether);
        assertEq(dsc.balanceOf(USER), 1_000 ether);
        assertEq(dsc.balanceOf(address(dsce)), 0);
    }

    // Verifies a user burn reverts when the engine has no DSC to burn. Scope: current _burnDsc balance dependency.
    function testBurnDscRevertsWhenEngineHasNoDscBalance() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, 100 ether);
        vm.prank(USER);
        dsc.approve(address(dsce), 100 ether);

        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_BurnAmmountExceedsBalance.selector);
        vm.prank(USER);
        dsce.burnDSC(100 ether);

        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 100 ether);
    }

    // Verifies debt cannot be burned beyond the recorded amount. Scope: debt accounting underflow and rollback.
    function testBurnDscRevertsWhenAmountExceedsDebt() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, 100 ether);

        vm.expectRevert();
        vm.prank(USER);
        dsce.burnDSC(101 ether);

        (uint256 debt,) = dsce.getAccountInformation(USER);
        assertEq(debt, 100 ether);
    }

    // Verifies the combined deposit-and-mint entry point. Scope: collateral transfer and safe DSC mint.
    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 1_000 ether);
        vm.stopPrank();

        (uint256 debt, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(debt, 1_000 ether);
        assertEq(collateralValueInUsd, 20_000 ether);
        assertEq(dsc.balanceOf(USER), 1_000 ether);
    }

    // Verifies DSC-backed redemption when the engine has DSC to burn. Scope: redemption event and state updates.
    function testRedeemCollateralForDsc() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_BURN);
        _fundEngineForBurn(AMOUNT_DSC_TO_BURN);
        vm.prank(USER);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_BURN);

        vm.expectEmit(true, true, true, true, address(dsce));
        emit collateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        dsce.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_BURN);

        (uint256 debt, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(debt, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(dsc.balanceOf(USER), AMOUNT_DSC_TO_BURN);
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE);
    }

    // Verifies normal DSC-backed redemption reverts without engine DSC. Scope: burn balance failure and rollback.
    function testRedeemCollateralForDscRevertsWhenEngineHasNoDscBalance() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_BURN);
        vm.prank(USER);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_BURN);

        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_BurnAmmountExceedsBalance.selector);
        vm.prank(USER);
        dsce.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_BURN);

        (uint256 debt, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(debt, AMOUNT_DSC_TO_BURN);
        assertEq(collateralValueInUsd, 20_000 ether);
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
    }

    // Verifies liquidations reject a healthy target. Scope: starting health-factor guard.
    function testLiquidateRevertsWhenUserHealthFactorIsOkay() public {
        vm.expectRevert(DSCEngine.DSCEngine__healthFactorOkay.selector);
        vm.prank(LIQUIDATOR);
        dsce.liquidate(weth, USER, 1 ether);
    }

    // Verifies liquidations reject zero debt coverage. Scope: liquidate's nonzero modifier.
    function testLiquidateRevertsForZeroDebtToCover() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(LIQUIDATOR);
        dsce.liquidate(weth, USER, 0);
    }

    // Verifies liquidation seizes collateral, burns DSC, and improves the target's health. Scope: full success path.
    function testLiquidateImprovesHealthFactor() public {
        _depositAndMint(USER, AMOUNT_COLLATERAL, 8_000 ether);
        _depositAndMint(LIQUIDATOR, LIQUIDATOR_COLLATERAL, 5_000 ether);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1_000e8);
        _fundEngineForBurn(2_000 ether);

        vm.prank(USER);
        uint256 startingHealthFactor = dsce.getHealthFactor();
        vm.prank(LIQUIDATOR);
        dsc.approve(address(dsce), 2_000 ether);
        vm.prank(LIQUIDATOR);
        dsce.liquidate(weth, USER, 2_000 ether);

        (uint256 debtAfter, uint256 collateralValueAfter) = dsce.getAccountInformation(USER);
        vm.prank(USER);
        uint256 endingHealthFactor = dsce.getHealthFactor();
        assertEq(debtAfter, 6_000 ether);
        assertEq(collateralValueAfter, 7_800 ether);
        assertGt(endingHealthFactor, startingHealthFactor);
        assertEq(ERC20Mock(weth).balanceOf(LIQUIDATOR), 2.2 ether);
    }

    // Verifies unauthorized accounts cannot mint DSC. Scope: Ownable access control.
    function testDscMintIsOwnerOnly() public {
        vm.expectRevert();
        vm.prank(USER);
        dsc.mint(USER, 1 ether);
    }

    // Verifies the owner cannot mint DSC to the zero address. Scope: mint recipient validation.
    function testDscMintRejectsZeroAddress() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_NotZeroAmount.selector);
        vm.prank(address(dsce));
        dsc.mint(address(0), 1 ether);
    }

    // Verifies the owner cannot mint a zero DSC amount. Scope: mint amount validation.
    function testDscMintRejectsZeroAmount() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_MustBeMoreThanZero.selector);
        vm.prank(address(dsce));
        dsc.mint(USER, 0);
    }

    // Verifies the owner can mint DSC and total supply tracks the recipient balance. Scope: successful mint.
    function testDscOwnerCanMint() public {
        vm.prank(address(dsce));
        bool minted = dsc.mint(USER, 5 ether);

        assertTrue(minted);
        assertEq(dsc.balanceOf(USER), 5 ether);
        assertEq(dsc.totalSupply(), 5 ether);
    }

    // Verifies unauthorized accounts cannot burn DSC. Scope: Ownable access control.
    function testDscBurnIsOwnerOnly() public {
        vm.expectRevert();
        vm.prank(USER);
        dsc.burn(1 ether);
    }

    // Verifies the owner cannot burn a zero DSC amount. Scope: burn amount validation.
    function testDscBurnRejectsZeroAmount() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_MustBeMoreThanZero.selector);
        vm.prank(address(dsce));
        dsc.burn(0);
    }

    // Verifies the owner cannot burn more DSC than it holds. Scope: owner balance validation.
    function testDscBurnRejectsAmountAboveOwnerBalance() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin_BurnAmmountExceedsBalance.selector);
        vm.prank(address(dsce));
        dsc.burn(1 ether);
    }

    // Verifies the owner can burn its balance and reduce total supply. Scope: successful burn.
    function testDscOwnerCanBurn() public {
        vm.prank(address(dsce));
        dsc.mint(address(dsce), 5 ether);

        vm.prank(address(dsce));
        dsc.burn(3 ether);

        assertEq(dsc.balanceOf(address(dsce)), 2 ether);
        assertEq(dsc.totalSupply(), 2 ether);
    }

    function _depositCollateral(address account, uint256 amount) internal {
        vm.startPrank(account);
        ERC20Mock(weth).approve(address(dsce), amount);
        dsce.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    function _depositAndMint(address account, uint256 collateralAmount, uint256 dscAmount) internal {
        vm.startPrank(account);
        ERC20Mock(weth).approve(address(dsce), collateralAmount);
        dsce.depositCollateralAndMintDsc(weth, collateralAmount, dscAmount);
        vm.stopPrank();
    }

    function _fundEngineForBurn(uint256 amount) internal {
        vm.prank(address(dsce));
        dsc.mint(address(dsce), amount);
    }
}
