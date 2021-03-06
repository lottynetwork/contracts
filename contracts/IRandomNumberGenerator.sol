//SPDX-License-Identifier: MIT
pragma solidity 0.8;

interface IRandomNumberGenerator {
    /**
     * Requests randomness from a user-provided seed
     */
    function getRandomNumber(uint256 lotteryId)
        external
        returns (bytes32 requestId);

    function viewLatestLotteryId() external view returns (uint256);
}
