 pragma solidity 0.8.4;

import "https://github.com/SwingbyProtocol/BEP20Token/blob/master/contracts/IBEP20.sol";
import "https://github.com/SwingbyProtocol/BEP20Token/blob/master/contracts/SafeMath.sol";
import "https://github.com/SwingbyProtocol/BEP20Token/blob/master/contracts/Context.sol";
import "https://github.com/SwingbyProtocol/BEP20Token/blob/master/contracts/Ownable.sol";
import "./IPancakeswapV2Factory.sol";
import "./IPancakeswapV2Router02.sol";

contract BNBHeroToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;

    address public bnbPoolAddress;
    
    uint256 private _tTotal = 100 * 10**6 * 10**18;
    uint256 private constant MAX = ~uint256(0);
    string private _name = "BNBHero";
    string private _symbol = "BNBH";
    uint8 private _decimals = 18;
    
    uint256 public _BNBFee = 11;
    uint256 private _previousBNBFee = _BNBFee;
    
    uint256 public _liquidityFee = 1;
    uint256 private _previousLiquidityFee = _liquidityFee;


    IPancakeswapV2Router02 public pancakeswapV2Router;
    address public pancakeswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public presaleEnded = false;
    
    uint256 public _maxTxAmount =  1 * 10**6 * 10**18;
    uint256 private numTokensToSwap =  1 * 10**4 * 10**18;
    uint256 public _balanceForLiquidity;
    uint256 public _balanceForBNBPool;
    
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );
    event ExcludedFromFee(address account);
    event IncludedToFee(address account);
    event UpdateFees(uint256 bnbFee, uint256 liquidityFee);
    event UpdatedMaxTaxPercent(uint256 maxTxPercent);
    event UpdateNumtokensToSwap(uint256 amount);
    event PancakeRouterChanged(address router);
    event UpdateBNBPoolAddress(address account);
    event SwapAndChargePool(uint256 token, uint256 bnbAmount);
    event TokenClaim(address tokenContract, uint256 amount);
    event Claim();
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor () {
        //Test Net
        //IPancakeswapV2Router02 _pancakeswapV2Router = IPancakeswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        //Mian Net
        IPancakeswapV2Router02 _pancakeswapV2Router = IPancakeswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        
        pancakeswapV2Pair = IPancakeswapV2Factory(_pancakeswapV2Router.factory())
            .createPair(address(this), _pancakeswapV2Router.WETH());

        // set the rest of the contract variables
        pancakeswapV2Router = _pancakeswapV2Router;
        
        //exclude owner and this contract from fee
        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[address(this)] = true;
        _tOwned[_msgSender()] = _tTotal;
        emit Transfer(address(0), owner(), _tTotal);
    }
    
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _tTotal;
    }
    
    function getOwner() external view override returns (address) {
        return owner();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function setRouterAddress(address newRouterAddress) external onlyOwner() {
        require(newRouterAddress != address(pancakeswapV2Router), 'This router is already used.');
        pancakeswapV2Router = IPancakeswapV2Router02(newRouterAddress);
        pancakeswapV2Pair = IPancakeswapV2Factory(pancakeswapV2Router.factory()).getPair(address(this), pancakeswapV2Router.WETH());
        if (pancakeswapV2Pair == address(0)) {
            pancakeswapV2Pair = IPancakeswapV2Factory(pancakeswapV2Router.factory()).createPair(address(this), pancakeswapV2Router.WETH());
        }
        emit PancakeRouterChanged(newRouterAddress);
    }

    function setBNBPoolAddress(address account) external onlyOwner {
        require(account != bnbPoolAddress, 'This address was already used');
        bnbPoolAddress = account;
        emit UpdateBNBPoolAddress(account);
    }
    
    function updatePresaleStatus(bool status) external onlyOwner {
        presaleEnded = status;
    }
    
    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFee(account);
    }
    
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludedToFee(account);
    }
    
    function setFees(uint256 bnbFee, uint256 liquidityFee) external onlyOwner() {
        _BNBFee = bnbFee;
        _liquidityFee = liquidityFee;
        emit UpdateFees(bnbFee, liquidityFee);
    }
   
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**2
        );
        emit UpdatedMaxTaxPercent(maxTxPercent);
    }
    
    function setNumTokensToSwap(uint256 amount) external onlyOwner() {
        numTokensToSwap = amount;
        emit UpdateNumtokensToSwap(amount);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }
    
     //to receive ETH from pancakeswapV2Router when swapping
    receive() external payable {}

    function _getFeeValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tBNBFee = tAmount.mul(_BNBFee).div(10**2);
        uint256 tLiquidity = tAmount.mul(_liquidityFee).div(10**2);
        uint256 tTransferAmount = tAmount.sub(tBNBFee).sub(tLiquidity);
        return (tTransferAmount, tBNBFee, tLiquidity);
    }

    function removeAllFee() private {
        if(_BNBFee == 0 && _liquidityFee == 0) return;
        
        _previousBNBFee = _BNBFee;
        _previousLiquidityFee = _liquidityFee;
        
        _BNBFee = 0;
        _liquidityFee = 0;
    }
    
    function restoreAllFee() private {
        _BNBFee = _previousBNBFee;
        _liquidityFee = _previousLiquidityFee;
    }
    
    function isExcludedFromFee(address account) external view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(to == pancakeswapV2Pair) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
            require(presaleEnded == true, "You are not allowed to add liquidity before presale is ended");
        }

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is pancakeswap pair.
        uint256 tokenBalance = _balanceForLiquidity;
        if(tokenBalance >= _maxTxAmount)
        {
            tokenBalance = _maxTxAmount;
        }
        
        bool overMinTokenBalance = tokenBalance >= numTokensToSwap;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != pancakeswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            tokenBalance = numTokensToSwap;
            _balanceForLiquidity = _balanceForLiquidity.sub(tokenBalance);
            //add liquidity
            swapAndLiquify(tokenBalance);
        }
        tokenBalance = _balanceForBNBPool;
        if(tokenBalance >= _maxTxAmount)
        {
            tokenBalance = _maxTxAmount;
        }

        overMinTokenBalance = tokenBalance >= numTokensToSwap;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != pancakeswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            tokenBalance = numTokensToSwap;
            _balanceForBNBPool = _balanceForBNBPool.sub(tokenBalance);
            swapAndChargeBNBPool(tokenBalance);
        }
        
        //indicates if fee should be deducted from transfer
        bool takeFee = false;
        if (from == pancakeswapV2Pair || to == pancakeswapV2Pair) {
            takeFee = true;
        }
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount,takeFee);
    }

    function swapAndChargeBNBPool(uint256 tokenBalance) private lockTheSwap {
        uint256 initialBalance = address(this).balance;

        swapTokensForEth(tokenBalance); 
        uint256 newBalance = address(this).balance.sub(initialBalance);
        (bool success, ) = payable(bnbPoolAddress).call{value: newBalance}("");
        require(success == true, "Transfer failed.");
        emit SwapAndChargePool(tokenBalance, newBalance);
    }

    function swapAndLiquify(uint256 tokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = tokenBalance.div(2);
        uint256 otherHalf = tokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to pancakeswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the pancakeswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeswapV2Router.WETH();

        _approve(address(this), address(pancakeswapV2Router), tokenAmount);

        // make the swap
        pancakeswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(pancakeswapV2Router), tokenAmount);

        // add the liquidity
        pancakeswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            bnbPoolAddress,
            block.timestamp
        );
        uint256 balance = address(this).balance;
        if (balance >= 0.1 ether){
            (bool success, ) = payable(bnbPoolAddress).call{value: balance}("");
            require(success, "Transfer failed.");
        }
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        (uint256 tTransferAmount, uint256 tBNBFee, uint256 tLiquidityFee) = _getFeeValues(amount);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);   
        _balanceForLiquidity = _balanceForLiquidity.add(tLiquidityFee); 
        _balanceForBNBPool = _balanceForBNBPool.add(tBNBFee);
        _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidityFee.add(tBNBFee));
        emit Transfer(sender, recipient, tTransferAmount);
        
        if(!takeFee)
            restoreAllFee();
    }

    function approveBNBHForPCS(address bnbHeroContract) public onlyOwner {
        _approve(bnbHeroContract, address(pancakeswapV2Router), MAX);
    }
    
}
