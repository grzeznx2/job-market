// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/BountyBay.sol";

contract BountyBayTest is Test {
    BountyBay public bountyBayContract;

    function setUp() public {
        bountyBayContract = new BountyBay();
    }
}
