// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
* @title DSCEngine
* @author olushola Emmanuel
*
* The system is designed to be as miniml aspossible, and its tokens maintain a 1 token == $1 peg
* This stable coin has the properties
* Exogeneous collateral
* our dsc system should be overcollaterised. value of collateral should always be > the amountof DSC
* ThiS contract is just the Erc20 implementation of our stable coin system
* It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH  and wBTC
* @noticethis conract is the core of the DSC system.
* @notice this contract is loosley based on makerDAO (DAI) system.
*/

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine_breaksHealthFactor(uint256 healthFactor);
    error DSCEngine_mintFailed();
    error DSCEngine__healthFactorOkay();
    error DSCEngine__HealthFactornotImproved();
    ////////////////////////////
    //////// State variables///////////
    ///////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralisedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    uint256 private constant LIQUIDATION_TRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    ////////////////////////////
    //////// Events ///////////
    ///////////////////////////
    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(
        address indexed redeemedFrom, address indexed addressRedeemedTo, address indexed token, uint256 amount
    );

    ////////////////////////////
    ////////Modifier ///////////
    ////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////////////////
    ///functions//
    ///////////////
    //come back to check tests for constructor
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }

        i_dsc = DecentralisedStableCoin(dscAddress);

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    *@param tokenCollateralAddress The collateral address to redeem
    * @param amountColateral The amount of collateral to redeem
    *@param amountDscToken The amount of DSC to burn
    *@Ths function burns and redeem underlying collateral in one transaction
    */

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);

        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeem collateral already checks health factor
    }

    /*
    * follows CEI
    * @param amountDscToMint the amount of DSC to mint
    * @notice they must have the collateral value more than the minimum threshhold
    *
    */

    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_mintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // Idont think this would hit
    }

    /*
    *@param colatral The erc20 collateral address to liquidate from the user
    *@param user The user who has broken the health factor. Their _healthFactor should
    * @notice you can partially liqudate a user
    *@you will get a user funds if you liquidates them
    *@ this function wrking assumes the project will be 200 percent undercolllaterised
    @notice a kown bug wuld be if the protocola was lessthan 100% undercollaterised
    */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine__healthFactorOkay();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalColateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalColateralToRedeem, user, msg.sender);
        //we have to burn the DSC

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactornotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((usdAmountInWei * PRECISION) / uint256(price) / ADDITIONAL_FEED_PRECISION);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    /////////////////////////////////////////
    //private and internal view functions////
    /////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscminted, uint256 collateralValueInUsd)
    {
        totalDscminted = s_DSCMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);
    }

    /*
    /* returns how close to liquidation a user is
    /* if  user gets to 0 they can get liquidated
    */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForTreshold = (collateralValueInUsd * LIQUIDATION_TRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalDscMinted;
    }

    // check healtfactor if they do have enoughcollateral
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_breaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////
    //pubblic and external functions///////
    ///////////////////////////////////////

    function _getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*
    *@param tokenCollateralAddress The Address of the token to deposit as collateral
    *@param amountcollteral The amount of collateral to deposit
    *@ amountDscToMint The amount of decentralised stablecoin to mint
    *@notice this function will deposit your collateral and mint Dsc in one transacton
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /*
    * level internal function, do mot call excepr function calling had checked health factor

      */
      //check if its addres(this) or dscFRO,

    function _burnDsc(uint256 amountOfDscToBurn, address onBehalfOf, address dscFrom) private  {
        s_DSCMinted[onBehalfOf] -= amountOfDscToBurn;
        bool success = i_dsc.transferFrom(msg.sender, dscFrom , amountOfDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountOfDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit collateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
