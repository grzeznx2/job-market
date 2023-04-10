// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Job.sol";

contract JobTest is Test {
    Job public jobContract;

    function setUp() public {
        jobContract = new Job();
    }
}
