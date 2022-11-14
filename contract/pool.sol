// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

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

contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
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
    // userAddress => betting balance
    mapping(address => uint256) public bettingBalance;
    // userAddress => isBetting boolean
    mapping(address => bool) public isBetting;

    uint256 public totalPoolStakedBalance;

    // betters userAddress Array
    address[] public betters;
    // stakers userAddress Array
    address[] public stakers;

    address internal cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event YieldWithdraw(address indexed to, uint256 amount);
    event FundAccount(address indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event UpdateWinning(address indexed to, uint256 amount);
    event UpdateBalance(address indexed to, uint256 amount);
    event PlayBet(address indexed to, uint256 amount);

    function stake(uint256 _amount) external {
        require(
            _amount > 0 &&
                IERC20Token(cUsdTokenAddress).balanceOf(msg.sender) >= _amount,
            "You cannot stake zero tokens"
        );

        IERC20Token(cUsdTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        totalPoolStakedBalance += _amount;
        stakingBalance[msg.sender] += _amount;
        dueTime[msg.sender] = block.timestamp + 15 days;
        isStaking[msg.sender] = true;
        if (hasStaked[msg.sender] == false) {
            stakers.push(msg.sender);
        }
        hasStaked[msg.sender] = true;
        emit Stake(msg.sender, _amount);
    }

    function distributeTransactionFee(uint256 _amount) private {
        require(_amount > 0, "You cannot add zero tokens");

        for (uint256 i = 0; i < stakers.length; i++) {
            if (isStaking[stakers[i]]) {
                uint256 balance = stakingBalance[stakers[i]];
                uint256 poolRatio = balance * _amount;
                uint256 yield = poolRatio / totalPoolStakedBalance;
                yieldBalance[stakers[i]] += yield;
            }
        }
    }

    function unstake(uint256 _amount) external {
        require(block.timestamp > dueTime[msg.sender], "unstake not yet due");

        require(
            _amount > 0 && stakingBalance[msg.sender] >= _amount,
            "You cannot unstake zero tokens"
        );

        dueTime[msg.sender] = block.timestamp;
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

    function withdrawYield() external {
        require(
            yieldBalance[msg.sender] > 0 && hasStaked[msg.sender],
            "You cannot withdraw zero tokens"
        );

        uint256 balance = yieldBalance[msg.sender];
        yieldBalance[msg.sender] = 0;
        IERC20Token(cUsdTokenAddress).transfer(msg.sender, balance);
        emit YieldWithdraw(msg.sender, balance);
    }

    function fundAccount(uint256 _amount) external {
        require(
            _amount > 0 &&
                IERC20Token(cUsdTokenAddress).balanceOf(msg.sender) >= _amount,
            "You cannot fund zero tokens"
        );

        uint256 balTransfer = _amount;
        _amount = 0;

        IERC20Token(cUsdTokenAddress).transferFrom(
            msg.sender,
            address(this),
            balTransfer
        );

        bettingBalance[msg.sender] += balTransfer;
        isBetting[msg.sender] = true;
        betters.push(msg.sender);
        emit FundAccount(msg.sender, balTransfer);
    }

    function calculateTransactionFee(uint256 _amount)
        public
        pure
        returns (uint256)
    {
        //get transaction fee
        uint256 fraction = _amount * 3;
        return fraction / 1000;
    }

    function withdraw(uint256 _amount, address _userAddress)
        external
        onlyOwner
    {
        require(_amount > 0, "You cannot claim zero tokens");

        uint256 balWithdraw = _amount;
        _amount = 0;

        uint256 transactionFee;
        (transactionFee) = calculateTransactionFee(balWithdraw);
        uint256 withdrawAmount = balWithdraw - transactionFee;

        distributeTransactionFee(transactionFee);

        IERC20Token(cUsdTokenAddress).transfer(_userAddress, withdrawAmount);

        emit Withdraw(_userAddress, withdrawAmount);
    }
}
