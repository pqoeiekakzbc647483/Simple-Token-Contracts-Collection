// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC20标准接口
 * @dev 定义ERC20代币标准的核心函数与事件
 * 所有符合ERC20标准的代币都必须实现该接口
 */
interface IERC20 {
    // 转账事件：from地址向to地址转账value数量代币时触发
    event Transfer(address indexed from, address indexed to, uint256 value);
    // 授权事件：owner地址授权spender地址使用value数量代币时触发
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // 获取代币总发行量
    function totalSupply() external view returns (uint256);
    // 获取指定账户的代币余额
    function balanceOf(address account) external view returns (uint256);
    // 调用者向目标地址转账代币
    function transfer(address to, uint256 amount) external returns (bool);
    // 查询授权额度：owner授权给spender的可用代币数量
    function allowance(address owner, address spender) external view returns (uint256);
    // 调用者授权给spender使用指定数量的代币
    function approve(address spender, uint256 amount) external returns (bool);
    // 代转账：从from地址向to地址转账，需提前获得授权
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title 上下文抽象合约
 * @dev 提供消息发送者获取功能，用于支持元交易等扩展场景
 */
abstract contract Context {
    // 获取当前交易的调用者地址，可被子合约重写
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

/**
 * @title 权限管理合约
 * @dev 基于Context实现，提供合约所有者权限控制功能
 * 核心：onlyOwner修饰器，限制仅合约所有者可调用关键函数
 */
contract Ownable is Context {
    // 合约所有者地址
    address private _owner;

    // 所有权转移事件：原所有者→新所有者时触发
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev 构造函数：部署合约时，将部署者设为初始所有者
     */
    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @dev 获取当前合约所有者地址
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev 仅所有者修饰器：调用函数前校验调用者是否为所有者
     * 非所有者调用会直接报错，终止交易
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev 转移合约所有权
     * @param newOwner 新所有者地址（不可为零地址）
     * 权限：仅当前所有者可调用
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @title 安全ERC20代币合约
 * @dev 实现完整ERC20标准 + 权限管理，可直接部署使用
 * 继承：IERC20（标准）、Ownable（权限）
 */
contract SecureToken is IERC20, Ownable {
    // 账户余额映射：地址 => 代币余额
    mapping(address => uint256) private _balances;
    // 授权额度映射：授权人 => 被授权人 => 可用额度
    mapping(address => mapping(address => uint256)) private _allowances;

    // 代币名称
    string private _name;
    // 代币符号（简称）
    string private _symbol;
    // 代币精度（小数点后位数，通用为18）
    uint8 private _decimals;
    // 代币总发行量
    uint256 private _totalSupply;

    /**
     * @dev 构造函数：初始化代币信息并铸造全部代币给部署者
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param decimals_ 代币精度
     * @param totalSupply_ 初始总发行量（未计算精度）
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        // 计算实际发行量：发行量 × 10^精度
        _totalSupply = totalSupply_ * (10**uint256(decimals_));
        // 将全部代币分配给合约部署者
        _balances[msg.sender] = _totalSupply;
        // 触发铸造代币事件（从零地址转账=铸造）
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    // ========== 基础信息查询函数 ==========
    // 获取代币名称
    function name() public view returns (string memory) { return _name; }
    // 获取代币符号
    function symbol() public view returns (string memory) { return _symbol; }
    // 获取代币精度
    function decimals() public view returns (uint8) { return _decimals; }
    // 获取代币总发行量（重写ERC20接口）
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    // 查询指定地址余额（重写ERC20接口）
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    /**
     * @dev 转账函数：调用者向目标地址转账
     * @param to 收款地址
     * @param amount 转账数量
     * @return 转账结果
     * 安全校验：禁止转账到零地址、余额充足
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != address(0), "ERC20: transfer to zero address");
        require(_balances[msg.sender] >= amount, "ERC20: insufficient balance");
        
        // 扣减发送者余额
        _balances[msg.sender] -= amount;
        // 增加接收者余额
        _balances[to] += amount;
        // 触发转账事件
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev 查询授权额度（重写ERC20接口）
     * @param owner 授权人地址
     * @param spender 被授权人地址
     * @return 可用授权额度
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev 授权函数：调用者授权他人使用自己的代币
     * @param spender 被授权人地址
     * @param amount 授权额度
     * @return 授权结果
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev 代转账函数：被授权人从授权账户转账
     * @param from 授权人地址（资金出处）
     * @param to 收款地址
     * @param amount 转账数量
     * @return 转账结果
     * 安全校验：地址非零、授权人余额充足、调用者授权额度充足
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(from != address(0) && to != address(0), "ERC20: zero address");
        require(_balances[from] >= amount && _allowances[from][msg.sender] >= amount);
        
        // 扣减授权额度
        _allowances[from][msg.sender] -= amount;
        // 扣减授权人余额
        _balances[from] -= amount;
        // 增加收款人余额
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @dev 增加授权额度：在原有授权基础上追加额度
     * @param spender 被授权人
     * @param addedValue 追加额度
     * @return 操作结果
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _allowances[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    /**
     * @dev 减少授权额度：在原有授权基础上减少额度
     * @param spender 被授权人
     * @param subtractedValue 减少额度
     * @return 操作结果
     * 安全校验：减少后额度不能为负数
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: allowance below zero");
        _allowances[msg.sender][spender] = currentAllowance - subtractedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }
}
