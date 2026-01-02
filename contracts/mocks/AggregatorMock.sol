// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AggregatorMock {
    uint8 private _decimals;
    int256 private _answer;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (uint80(0), _answer, uint256(0), uint256(0), uint80(0));
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 a) external {
        _answer = a;
    }
}
