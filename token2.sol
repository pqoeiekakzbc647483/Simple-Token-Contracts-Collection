// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC20 标准接口
 * @dev 定义ERC20代币必须实现的核心方法与事件
 */
interface IERC20 {
    // 转账事件：记录from地址向to地址转账value数量
    event Transfer(address indexed from, address indexed to, uint256 value);
    // 授权事件：记录owner地址授权spender地址可使用amount数量
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // 获取代币总发行量
    function totalSupply() external view returns (uint256);
    // 查询指定账户的代币余额
    function balanceOf(address account) external view returns (uint256);
    // 调用者向目标地址转账
    function transfer(address to, uint256 amount) external returns (bool);
    // 查询授权额度：owner授权给spender的可用额度
    function allowance(address owner, address spender) external view returns (uint256);
    // 调用者授权spender可使用自己的代币
    function approve(address spender, uint256 amount) external returns (bool);
    // 从from地址转账到to地址（需提前授权）
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title 上下文工具合约
 * @dev 提供消息发送者获取方法，便于后续扩展
 */
abstract contract Context {
    // 获取当前交易的调用者地址
    function _msgSender() internal view virtual returns (address) { 
        return msg.sender; 
    }
}

/**
 * @title 权限控制合约
 * @dev 实现管理员、经理双重权限管理
 */
contract OwnerControl is Context {
    // 最高管理员地址
    address private _admin;
    // 运营经理地址
    address private _manager;
    
    // 构造函数：部署时将部署者设为管理员和经理
    constructor() {
        _admin = _msgSender();
        _manager = _msgSender();
    }
    
    // 修饰器：仅管理员可调用
    modifier onlyAdmin() {
        require(_msgSender() == _admin, "Not admin");
        _;
    }
    
    // 修饰器：管理员或经理可调用
    modifier onlyManager() {
        require(_msgSender() == _admin || _msgSender() == _manager, "Not manager");
        _;
    }
    
    // 管理员设置新的经理地址
    function setManager(address newManager) external onlyAdmin {
        _manager = newManager;
    }

    // 获取管理员地址（外部可读）
    function admin() public view returns (address) {
        return _admin;
    }

    // 获取经理地址（外部可读）
    function manager() public view returns (address) {
        return _manager;
    }
}

/**
 * @title 反机器人代币合约
 * @dev 实现ERC20标准 + 黑名单功能，防止机器人恶意交易
 */
contract AntiBotToken is IERC20, OwnerControl {
    // 代币名称
    string private _name;
    // 代币符号
    string private _symbol;
    // 代币精度（小数点后位数）
    uint8 private _decimals;
    // 代币总发行量
    uint256 private _totalSupply;
    
    // 余额映射：地址 => 余额
    mapping(address => uint256) private _balances;
    // 授权映射：持有者 => 被授权者 => 额度
    mapping(address => mapping(address => uint256)) private _allowances;
    // 黑名单映射：地址 => 是否被封禁
    mapping(address => bool) private _blacklist;
    
    /**
     * @dev 构造函数：初始化代币信息
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param decimals_ 代币精度
     * @param supply_ 发行总量（未计算精度）
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 supply_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        // 计算带精度的总发行量
        _totalSupply = supply_ * 10**uint256(decimals_);
        // 将全部代币分配给部署者
        _balances[_msgSender()] = _totalSupply;
        // 触发铸造代币事件
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }
    
    /**
     * @dev 设置黑名单（仅经理/管理员）
     * @param account 目标地址
     * @param status 封禁/解封状态
     */
    function blacklist(address account, bool status) external onlyManager {
        _blacklist[account] = status;
    }
    
    // 获取代币名称
    function name() public view returns (string memory) { return _name; }
    // 获取代币符号
    function symbol() public view returns (string memory) { return _symbol; }
    // 获取代币精度
    function decimals() public view returns (uint8) { return _decimals; }
    // 获取代币总发行量（重写接口方法）
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    // 查询地址余额（重写接口方法）
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    
    /**
     * @dev 内部转账核心逻辑
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 转账数量
     */
    function _transfer(address from, address to, uint256 amount) internal {
        // 禁止零地址转账
        require(from != address(0) && to != address(0), "Zero address");
        // 禁止黑名单地址交易
        require(!_blacklist[from] && !_blacklist[to], "Blacklisted");
        // 检查转出地址余额充足
        require(_balances[from] >= amount, "Insufficient balance");
        
        // 执行余额增减
        _balances[from] -= amount;
        _balances[to] += amount;
        // 触发转账事件
        emit Transfer(from, to, amount);
    }
    
    /**
     * @dev 外部转账：调用者转给他人
     */
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }
    
    /**
     * @dev 查询授权额度（重写接口方法）
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @dev 授权他人使用自己的代币
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }
    
    /**
     * @dev 授权转账：从他人地址转账（需提前授权）
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        // 检查授权额度足够
        require(_allowances[from][_msgSender()] >= amount, "Allowance exceeded");
        // 扣除授权额度
        _allowances[from][_msgSender()] -= amount;
        // 执行转账
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev 查询地址是否在黑名单
     */
    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }
}
