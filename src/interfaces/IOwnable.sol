// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.11;

interface IOwnable {
    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;
}
