// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./EASTr.sol";

contract EASTrIsLAUndGOD {
    address public immutable FEE_TOKEN;
    address public immutable WALLET_90; 
    address public immutable WALLET_10; 
    uint256 public deployCount;
    uint256 public constant INITIAL_FEE = 1 * 10**18;

    event EASTrDeployed(address indexed creator, address indexed EASTrAddress);

    constructor(
        address _feeToken,
        address _wallet90,
        address _wallet10
    ) {
        FEE_TOKEN = _feeToken;
        WALLET_90 = _wallet90;
        WALLET_10 = _wallet10;
    }

    function EASTrIsLAUndTaxCollector(
        string calldata name,
        string calldata ticker,
        uint256 supply,
        address rewardToken,
        uint256 rewardPercentage,
        uint256 tokenFee
    ) external returns (address payable token) {
        require(supply > 0 && rewardPercentage <= 100 && tokenFee <= 100);

        uint256 deployFee = deployCount < 100 ? INITIAL_FEE : INITIAL_FEE * (1 + ((deployCount - 100) / 10));

        require(IERC20(FEE_TOKEN).transferFrom(msg.sender, WALLET_90, (deployFee * 90) / 100));
        require(IERC20(FEE_TOKEN).transferFrom(msg.sender, WALLET_10, deployFee / 10));

        token = payable (address(new EASTr(
            name,
            ticker,
            supply,
            rewardToken,
            tokenFee
        )));

        EASTr(token).setSplit(rewardPercentage);
        EASTr(token).setTaxCollector(msg.sender);
        EASTr(token).transferOwnership(msg.sender);

        uint256 contractBalance = EASTr(token).balanceOf(address(this));
        if (contractBalance > 0) {
            EASTr(token).transfer(msg.sender, contractBalance);
        }

        unchecked { deployCount++; }
        emit EASTrDeployed(msg.sender, token);
        
    }
}
