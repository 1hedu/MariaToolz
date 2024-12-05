// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface ILAU {
    function maxSupply() external view returns (uint256);
}

interface IPulseXRouter {
    function factory() external pure returns (address);
    function WPLS() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}

interface IPulseXPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
}

interface IPulseXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if(currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from zero");
        require(recipient != address(0), "ERC20: transfer to zero");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero");

        _totalSupply += amount;
        _balances[account] = amount;
        emit Transfer(address(0), account, amount);
    }
}
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Caller is not owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract FALLAUT is ERC20, Ownable {
    struct PairInfo {
        address pair;           
        address plsPair;       
        address token;         
        bool established;      
    }

    uint256 public constant TAX_RATE = 5;    
    uint256 public constant TOTAL_SUPPLY = 1000000 * 10**18;
    uint256 public constant MIN_PLS_FOR_OPS = 0.01 ether;
    
    address public immutable WPLS;
    IPulseXRouter public immutable router;
    IPulseXFactory public immutable factory;
    
    address public PLP0;             
    address public currentPLPF;      
    uint256 public currentLevel;     
    
    mapping(uint256 => PairInfo) public pairs;
    mapping(address => bool) public registeredTokens;
    mapping(address => bool) public _isExcludedFromFees;
    mapping(address => bool) public isRegisteredPair;
    
    bool private swapping;
    bool public launched;
    bool public swapEnabled = true;
    uint256 public tradingActiveTime;
    uint256 public plsStack;

    event SwapEnabledUpdated(bool enabled);
    event Launched(address indexed plp0, address indexed plpf);
    event TokenRegistered(address indexed token, uint256 amount, uint256 level);
    event PermanentPairCreated(uint256 indexed level, address plsPair, uint256 plsAmount);
    event PLPFUpdated(address indexed oldPLPF, address indexed newPLPF, uint256 level);
    event TaxCollected(uint256 fallautAmount, uint256 plsReceived);
    event PLSDistributed(uint256 level, address plsPair, uint256 amount);
    
    constructor() ERC20("Fallaut", "FALLAUT") {
        router = IPulseXRouter(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
        factory = IPulseXFactory(router.factory());
        WPLS = router.WPLS();
        
        _mint(msg.sender, TOTAL_SUPPLY);
        _approve(address(this), address(router), type(uint256).max);

        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
    }

    receive() external payable {}

    function toggleSwap() external onlyOwner {
        swapEnabled = !swapEnabled;
        emit SwapEnabledUpdated(swapEnabled);
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
    }

    function setRegisteredPair(address, bool) external onlyOwner {
    isRegisteredPair[factory.getPair(address(this), WPLS)] = true;
    }   

    function launch(address _PLP0, address _PLPF) external onlyOwner {
        require(!launched, "Already launched");
        require(_PLP0 != address(0) && _PLPF != address(0), "Invalid addresses");
        require(msg.sender == tx.origin, "Only EOA");
        
        IPulseXPair pair = IPulseXPair(_PLP0);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "PLP0 not ready");
        
        IPulseXPair plpf = IPulseXPair(_PLPF);
        require(
            (plpf.token0() == address(this) && plpf.token1() == _PLP0) ||
            (plpf.token0() == _PLP0 && plpf.token1() == address(this)),
            "Invalid PLPF"
        );
        
        require(plpf.balanceOf(address(this)) > 0, "No PLPF owned");
        
        PLP0 = _PLP0;
        currentPLPF = _PLPF;
        
        pairs[0] = PairInfo({
            pair: _PLP0,
            plsPair: address(0),
            token: address(0),
            established: false
        });

        launched = true;
        tradingActiveTime = block.number;
        emit Launched(_PLP0, _PLPF);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0) && to != address(0), "Invalid address");
        
        // Allow transfers before launch only if either party is excluded from fees
        if(tradingActiveTime == 0) {
            require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading not active");
            super._transfer(from, to, amount);
            return;
        }

        // Skip tax handling during swaps or for excluded addresses
        if(swapping || _isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }

        uint256 fees = (amount * TAX_RATE) / 100;
        uint256 transferAmount = amount - fees;
        
        if(fees > 0) {
            super._transfer(from, address(this), fees);
            
            // Only process taxes when selling (transferring to a registered pair)
            if(swapEnabled && isRegisteredPair[to]) {
                swapping = true;
                _handleTax();
                swapping = false;
            }
        }
        
        super._transfer(from, to, transferAmount);
    }

    function _handleTax() private {
        uint256 fallautBalance = balanceOf(address(this));
        if(fallautBalance == 0) return;
        
        _swapFallautForPLS(fallautBalance);
        
        uint256 plsBalance = address(this).balance;
        if(plsBalance > MIN_PLS_FOR_OPS) {
            uint256 toStack = plsBalance / 2;
            plsStack += toStack;
            
            if(plsBalance > toStack) {
                _distributePLS(plsBalance - toStack);
            }
        }
    }
    function registerToken(address token) external {
    require(launched, "Not launched");
    require(!registeredTokens[token], "Already registered");
    require(token != address(0), "Invalid token");

    // Ensure the caller holds at least 100 Fallaut tokens
    uint256 fallautBalance = balanceOf(msg.sender);
    require(fallautBalance >= 100 * 10**18, "You must hold at least 100 Fallaut tokens");

    uint256 maxWithDecimals = ILAU(token).maxSupply() * 10**IERC20Metadata(token).decimals();
    uint256 requiredAmount = maxWithDecimals / 100;
    
    uint256 preBalance = IERC20(token).balanceOf(address(this));
    require(IERC20(token).transferFrom(msg.sender, address(this), requiredAmount), "Transfer failed");
    require(IERC20(token).balanceOf(address(this)) - preBalance == requiredAmount, "Invalid transfer amount");

    uint256 plpfBalance = IERC20(currentPLPF).balanceOf(address(this));
    require(plpfBalance > 0, "No PLPF to break");
    
    uint256 preFallautBalance = balanceOf(address(this));
    uint256 currentTopPLPBalance = IERC20(getCurrentTopPLP()).balanceOf(address(this));
    
    _removeLiquidity(currentPLPF);
    
    uint256 fallautReceived = balanceOf(address(this)) - preFallautBalance;
    uint256 plpReceived = IERC20(getCurrentTopPLP()).balanceOf(address(this)) - currentTopPLPBalance;
    require(fallautReceived > 0 && plpReceived > 0, "Liquidity break failed");

    uint256 plpForNewPair = plpReceived / 2;
    uint256 plpForPLS = plpReceived - plpForNewPair;

    address previousPLP = getCurrentTopPLP();
    address newPLP = factory.createPair(previousPLP, token);
    require(factory.getPair(previousPLP, token) == newPLP, "Pair creation failed");

    IERC20(previousPLP).approve(address(router), plpForNewPair);
    IERC20(token).approve(address(router), requiredAmount);
    router.addLiquidity(
        previousPLP,
        token,
        plpForNewPair,
        requiredAmount,
        0,
        0,
        address(this),
        block.timestamp + 300
    );

    if(plsStack >= MIN_PLS_FOR_OPS) {
        _createAndAddPLSPair(previousPLP, plpForPLS);
    }

    address newPLPF = factory.createPair(address(this), newPLP);
    require(factory.getPair(address(this), newPLP) == newPLPF, "PLPF creation failed");

    _approve(address(this), address(router), fallautReceived);
    IERC20(newPLP).approve(address(router), type(uint256).max);
    router.addLiquidity(
        address(this),
        newPLP,
        fallautReceived,
        IERC20(newPLP).balanceOf(address(this)),
        0,
        0,
        address(this),
        block.timestamp + 300
    );

    address oldPLPF = currentPLPF;
    currentPLPF = newPLPF;
    pairs[currentLevel] = PairInfo({
        pair: newPLP,
        plsPair: address(0),
        token: token,
        established: false
    });
    
    registeredTokens[token] = true;
    currentLevel++;
    
    emit TokenRegistered(token, requiredAmount, currentLevel - 1);
    emit PLPFUpdated(oldPLPF, newPLPF, currentLevel - 1);   
    }


    function _createAndAddPLSPair(address token, uint256 tokenAmount) private {
        
        address plsPair = factory.createPair(token, WPLS);
        require(factory.getPair(token, WPLS) == plsPair, "PLS pair creation failed");
        isRegisteredPair[plsPair] = true;
        IERC20(token).approve(address(router), tokenAmount);
        _addPLSLiquidity(token, plsStack, tokenAmount);
        
        pairs[currentLevel - 1].plsPair = plsPair;
        pairs[currentLevel - 1].established = true;
        
        emit PermanentPairCreated(currentLevel - 1, plsPair, plsStack);
        plsStack = 0;
    }

    function _addPLSLiquidity(address token, uint256 plsAmount, uint256 tokenAmount) private {
        require(plsAmount >= MIN_PLS_FOR_OPS, "Insufficient PLS");
        
        uint256 swapAmount = plsAmount / 2;
        uint256 liquidityAmount = plsAmount - swapAmount;
        
        address[] memory path = new address[](2);
        path[0] = WPLS;
        path[1] = token;
        
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: swapAmount}(
            0,
            path,
            address(this),
            block.timestamp + 300
        );
        
        IERC20(token).approve(address(router), tokenAmount);
        router.addLiquidityETH{value: liquidityAmount}(
            token,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 300
        );
    }

    function _removeLiquidity(address pair) private {
        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        if(liquidity > 0) {
            IERC20(pair).approve(address(router), liquidity);
            IPulseXPair lpair = IPulseXPair(pair);
            router.removeLiquidity(
                lpair.token0(),
                lpair.token1(),
                liquidity,
                0,
                0,
                address(this),
                block.timestamp + 300
            );
        }
    }

    function _swapFallautForPLS(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WPLS;
        
        uint256 balanceBefore = address(this).balance;
        
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp + 300
        );
        
        uint256 plsReceived = address(this).balance - balanceBefore;
        emit TaxCollected(amount, plsReceived);
    }

    function _distributePLS(uint256 amount) private {
        if(currentLevel == 0) return;
        
        uint256 plsPerPair = amount / currentLevel;
        if(plsPerPair < MIN_PLS_FOR_OPS) return;
        
        for(uint256 i = 0; i < currentLevel; i++) {
            PairInfo storage pairInfo = pairs[i];
            if(pairInfo.established) {
                _addPLSLiquidity(pairInfo.pair, plsPerPair, IERC20(pairInfo.pair).balanceOf(address(this)));
                emit PLSDistributed(i, pairInfo.plsPair, plsPerPair);
            }
        }
    }

    function getCurrentTopPLP() public view returns (address) {
        if (currentLevel == 0) return PLP0;
        return pairs[currentLevel - 1].pair;
    }
    
    function getCurrentPLPF() external view returns (address) {
        return currentPLPF;
    }
    
    function getCurrentPairs() external view returns (address topPLP, address plpf) {
        topPLP = getCurrentTopPLP();
        plpf = currentPLPF;
    }
}
