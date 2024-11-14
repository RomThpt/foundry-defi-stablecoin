// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author RomThpt
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //    Errors     //
    ///////////////////
    error DSCEngine__NotZeroAddress();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed(address token);
    error DSSEngine__BreackHealthFactor(uint256 userHealthFactor);

    /////////////////////////
    //   State Variables   //
    /////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized

    ///////////////////
    //   Modifier   //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    //   Functions   //
    ///////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////

    function depositCollaterAndMintDsc() external {}

    /*
    * @param _tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
    * @param _amountCollateral: The amount of collateral you're depositing
    */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        if (address(0) == _tokenCollateralAddress) {
            revert DSCEngine__NotZeroAddress();
        }
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}
    /*
    * @notice follow CEI
    * @param _amountDscToMint The amount of decentralized stablecoin to mint 
    * @notice they must have more collateral than the minimum threshold
    */

    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;
        _revertIfHelthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////////////
    //  Private and Internal view Functions  //
    ///////////////////////////////////////////

    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[_user];
        collateralValueInUsd = _getAccountCollateralValue(_user);
        return (totalDscMinted, collateralValueInUsd);
    }

    /*
    * @notice calculate of how close you are from liquidation if >1
    *
    * 
    */
    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
        // 100 *50 = 5 000 /100 = 50
    }

    function _revertIfHelthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < 1) {
            revert DSSEngine__BreackHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////
    //    Public View Functions  //
    ///////////////////////////////
    function _getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * _amount * 1e10) / 1e18;
    }
}
