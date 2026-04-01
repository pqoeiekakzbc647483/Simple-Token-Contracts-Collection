
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

abstract contract Context { function _msgSender() internal view virtual returns (address) { return msg.sender; } }
contract Ownable is Context {
    address private _owner; constructor() { _owner = _msgSender(); }
    function owner() public view returns (address) { return _owner; }
    modifier onlyOwner() { require(_owner == _msgSender(), "!owner"); _; }
}

contract PremiumBusinessToken is IERC20, Ownable {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _excludedFromFee;
    
    uint256 public taxFee = 20; // 2.0%
    uint256 public dividendFee = 10; // 1.0%
    uint256 public totalFee = 30;
    address public feeReceiver;
    
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 supply_, address feeTo) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = supply_ * 10**uint256(decimals_);
        feeReceiver = feeTo;
        _excludedFromFee[msg.sender] = true;
        _excludedFromFee[address(this)] = true;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
    function excludeFromFee(address account, bool status) external onlyOwner {
        _excludedFromFee[account] = status;
    }
    
    function setFees(uint256 tax, uint256 dividend) external onlyOwner {
        taxFee = tax;
        dividendFee = dividend;
        totalFee = tax + dividend;
        require(totalFee <= 1000, "Fee too high");
    }
    
    function setFeeReceiver(address newReceiver) external onlyOwner {
        feeReceiver = newReceiver;
    }
    
    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0));
        require(_balances[from] >= amount);
        
        if(_excludedFromFee[from] || _excludedFromFee[to] || totalFee == 0){
            _balances[from] -= amount;
            _balances[to] += amount;
        } else {
            uint256 fees = (amount * totalFee) / 1000;
            uint256 sendAmount = amount - fees;
            
            _balances[from] -= amount;
            _balances[to] += sendAmount;
            _balances[feeReceiver] += fees;
        }
        emit Transfer(from, to, amount);
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_allowances[from][_msgSender()] >= amount);
        _allowances[from][_msgSender()] -= amount;
        _transfer(from, to, amount);
        return true;
    }
}
