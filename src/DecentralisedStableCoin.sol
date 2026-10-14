// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title Decentralisdstablecoin
* @author olushola Emmanuel
* collateral : Exogeneous
* minting : Algorithmic
* Relative stability
* ThiS contract is just the Erc20 implementation of our stablee coin system
*/

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin_BurnAmmountExceedsBalance();
    error DecentralisedStableCoin_MustBeMoreThanZero();
    error DecentralisedStableCoin_NotZeroAmount();
    error DecentralisedStableCoin_AmountShouldExceedZero();

    constructor() ERC20("DecentralisedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount == 0) {
            revert DecentralisedStableCoin_MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralisedStableCoin_BurnAmmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin_NotZeroAmount();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

