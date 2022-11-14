// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Token {
    function transfer(address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}


contract Pool is Ownable {
    // userAddress => stakingBalance
    mapping(address => uint256) public stakingBalance;
    // userAddress => isStaking boolean
    mapping(address => bool) public isStaking;
    // userAddress => isStaking boolean
    mapping(address => bool) public hasStaked;
    // userAddress => timeStamp
    mapping(address => uint256) public dueTime;
    // userAddress => yields
    mapping(address => uint256) public yieldBalance;

    uint256 public totalPoolStakedBalance;

    // stakers userAddress Array
    address[] public stakers;

    address internal cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    uint public transactionFee = 0.002 ether;

    uint public feesCollected;

    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event YieldWithdraw(address indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    /**
     * @dev allow users to stake CUSD tokens they own to receive rewards
     * @param _amount the amount sender wishes to stake. Must be at least 0.01 CUSD
     * @notice staking period is 2 minutes
     */
    function stake(uint256 _amount) external payable {
        require(
            _amount >= 0.01 ether &&
                IERC20Token(cUsdTokenAddress).balanceOf(msg.sender) >= _amount,
            "You cannot stake zero tokens"
        );

        IERC20Token(cUsdTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint amountToAddToBalance = _amount  - transactionFee;
        feesCollected += transactionFee;

        uint newTotalPoolStakedBalance = totalPoolStakedBalance + amountToAddToBalance; 
        totalPoolStakedBalance = newTotalPoolStakedBalance;

        uint newStakingBalance = stakingBalance[msg.sender] + amountToAddToBalance;
        stakingBalance[msg.sender] = newStakingBalance;

        dueTime[msg.sender] = block.timestamp + 2 minutes;
        isStaking[msg.sender] = true;
        if (hasStaked[msg.sender] == false) {
            stakers.push(msg.sender);
            hasStaked[msg.sender] = true;
        }
        emit Stake(msg.sender, _amount);
    }

    // function to distribute yield rewards to stakers
    function distributeTransactionFee(uint256 _amount) public {
        uint stakersLength = stakers.length;
        for (uint256 i = 0; i < stakersLength; i++) {
            if (isStaking[stakers[i]]) {
                // basis points are used to increase accuracy for precision
                // pool ratio is the percentage representing the amount user has staked over the total staked amount
                // based off this percentage, users are rewarded this percentage from the fees collected
                uint256 poolRatio = (stakingBalance[stakers[i]] * 10000) / totalPoolStakedBalance;
                uint256 yield = (_amount * poolRatio) / 10000;
                yieldBalance[stakers[i]] += yield;
            }
        }
    }

    /**
        * @dev allow users to unstake a certain amount they had previously staked
        * @notice staking period needs to be over
     */
    function unstake(uint256 _amount) external payable {
        require(block.timestamp > dueTime[msg.sender], "unstake not yet due");

        require(
            _amount > 0 && stakingBalance[msg.sender] >= _amount,
            "You cannot unstake zero tokens"
        );
        uint256 balTransfer = _amount;
        _amount = 0;
        stakingBalance[msg.sender] -= balTransfer;
        totalPoolStakedBalance -= balTransfer;
        if (stakingBalance[msg.sender] == 0) {
            isStaking[msg.sender] = false;
        }
        IERC20Token(cUsdTokenAddress).transfer(msg.sender, balTransfer);
        emit Unstake(msg.sender, balTransfer);
    }

    /**
        * @dev allow users to withdraw their yield rewards
     */
    function withdrawYield() public payable {
        require(
            yieldBalance[msg.sender] > 0 && hasStaked[msg.sender],
            "You cannot withdraw zero tokens"
        );

        uint256 balance = yieldBalance[msg.sender];
        yieldBalance[msg.sender] = 0;
        IERC20Token(cUsdTokenAddress).transfer(msg.sender, balance);
        emit YieldWithdraw(msg.sender, balance);
    }


    /**
        * @dev allow the owner to distribute the feesCollected amount to stakers and also to take his percentage
     */
    function withdraw(address _userAddress)
        public payable
        onlyOwner
    {
        require(feesCollected >= 0.1 ether, "You cannot claim zero tokens");
        require(_userAddress != address(0), "Address zero is not a valid receiver address");

        // basis points are used to increase accuracy for precision
        // 10% of the fees collected goes to the owner
        uint256 withdrawAmount = (feesCollected * 1000) / 10000;
        distributeTransactionFee(feesCollected - withdrawAmount);
        feesCollected = 0;

        IERC20Token(cUsdTokenAddress).transfer(_userAddress, withdrawAmount);

        emit Withdraw(_userAddress, withdrawAmount);
    }
}
