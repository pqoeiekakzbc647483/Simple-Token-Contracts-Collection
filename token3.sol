// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ERC20标准代币接口，定义必须实现的方法和事件
interface IERC20 {
    // 转账事件：from 转给 to 价值 value
    event Transfer(address indexed from, address indexed to, uint256 value);
    // 授权事件：owner 授权 spender 可使用额度 value
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // 获取代币总供应量
    function totalSupply() external view returns (uint256);
    // 查询某个地址的余额
    function balanceOf(address account) external view returns (uint256);
    // 调用者直接转账给 to
    function transfer(address to, uint256 amount) external returns (bool);
    // 查询 owner 授权给 spender 的额度
    function allowance(address owner, address spender) external view returns (uint256);
    // 调用者授权 spender 可使用自己的代币
    function approve(address spender, uint256 amount) external returns (bool);
    // 从 from 地址代转代币到 to（需授权）
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// 上下文合约，用于获取消息发送者，方便扩展
abstract contract Context { 
    function _msgSender() internal view virtual returns (address) { 
        return msg.sender; 
    } 
}

// 所有权控制合约，只有所有者能调用特权方法
contract Ownable is Context {
    // 合约所有者地址
    address private _owner; 

    // 构造函数：部署者自动成为所有者
    constructor() { 
        _owner = _msgSender(); 
    }

    // 查询当前所有者
    function owner() public view returns (address) { 
        return _owner; 
    }

    // 修饰器：仅合约所有者可调用
    modifier onlyOwner() { 
        require(_owner == _msgSender(), "!owner"); 
        _; 
    }
}

// 高级商用代币合约（带手续费、分红、免税白名单）
contract PremiumBusinessToken is IERC20, Ownable {
    // 代币名称
    string private _name;
    // 代币符号
    string private _symbol;
    // 代币精度（小数点后几位）
    uint8 private _decimals;
    // 代币总发行量
    uint256 private _totalSupply;

    // 地址余额映射：地址 => 余额
    mapping(address => uint256) private _balances;
    // 授权映射：持有者 => 被授权者 => 授权额度
    mapping(address => mapping(address => uint256)) private _allowances;
    // 手续费豁免名单：地址 => 是否免手续费
    mapping(address => bool) private _excludedFromFee;

    // 交易税费率：2.0%（分母 1000）
    uint256 public taxFee = 20;
    // 分红费率：1.0%
    uint256 public dividendFee = 10;
    // 总费率 = 税 + 分红
    uint256 public totalFee = 30;
    // 手续费接收地址
    address public feeReceiver;

    /**
     * @dev 构造函数：初始化代币信息
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param decimals_ 精度
     * @param supply_ 发行总量（未乘精度）
     * @param feeTo 手续费接收地址
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 supply_, address feeTo) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        // 计算带精度的总发行量
        _totalSupply = supply_ * 10**uint256(decimals_);
        // 设置手续费接收地址
        feeReceiver = feeTo;

        // 默认部署者和合约本身免手续费
        _excludedFromFee[msg.sender] = true;
        _excludedFromFee[address(this)] = true;

        // 全部代币分配给部署者
        _balances[msg.sender] = _totalSupply;
        // 触发铸造事件
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    /**
     * @dev 设置地址是否免手续费（仅所有者）
     * @param account 目标地址
     * @param status 状态：true=免手续费，false=收手续费
     */
    function excludeFromFee(address account, bool status) external onlyOwner {
        _excludedFromFee[account] = status;
    }

    /**
     * @dev 设置费率（仅所有者）
     * @param tax 交易税
     * @param dividend 分红税
     */
    function setFees(uint256 tax, uint256 dividend) external onlyOwner {
        taxFee = tax;
        dividendFee = dividend;
        totalFee = tax + dividend;
        // 限制总费率不超过 10%
        require(totalFee <= 1000, "Fee too high");
    }

    /**
     * @dev 修改手续费接收地址（仅所有者）
     */
    function setFeeReceiver(address newReceiver) external onlyOwner {
        feeReceiver = newReceiver;
    }

    // 获取代币名称
    function name() public view returns (string memory) { return _name; }
    // 获取代币符号
    function symbol() public view returns (string memory) { return _symbol; }
    // 获取精度
    function decimals() public view returns (uint8) { return _decimals; }
    // 获取总发行量
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    // 查询地址余额
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    /**
     * @dev 内部转账核心逻辑（含手续费逻辑）
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 转账数量
     */
    function _transfer(address from, address to, uint256 amount) internal {
        // 禁止零地址转账
        require(from != address(0) && to != address(0));
        // 检查转出余额充足
        require(_balances[from] >= amount);

        // 判断是否免手续费：转出/转入在白名单 或 总费率为0
        if(_excludedFromFee[from] || _excludedFromFee[to] || totalFee == 0){
            // 无手续费：全额转账
            _balances[from] -= amount;
            _balances[to] += amount;
        } else {
            // 有手续费：计算费用和实际到账金额
            uint256 fees = (amount * totalFee) / 1000;
            uint256 sendAmount = amount - fees;
            
            // 扣减发送者余额
            _balances[from] -= amount;
            // 接收者收到扣除手续费后的金额
            _balances[to] += sendAmount;
            // 手续费打入手续费地址
            _balances[feeReceiver] += fees;
        }

        // 触发转账事件（日志显示原始转账金额）
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
     * @dev 查询授权额度
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev 授权他人使用代币
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev 授权代转：从 from 转给 to（需授权）
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        // 检查授权额度足够
        require(_allowances[from][_msgSender()] >= amount);
        // 扣减授权额度
        _allowances[from][_msgSender()] -= amount;
        // 执行转账
        _transfer(from, to, amount);
        return true;
    }
}
