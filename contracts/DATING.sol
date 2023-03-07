//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interface/IReflectionToken.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

contract ReflectionToken is IReflectionToken, Ownable {
    struct FeeTier {
        uint256 developmentFee;
        uint256 taxFee;
        uint256 staffFee;
        uint256 marketingFee;
        uint256 liquidityFee;
        address developmentWallet;
        address staffWallet;
        address marketingWallet;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tDevelopment;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tStaff;
        uint256 tMarketing;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tDevelopment;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tStaff;
        uint256 tMarketing;
    }

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isBlacklisted;
    mapping(address => uint256) private _accountsTier;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    uint256 public maxFee;

    string private _name;
    string private _symbol;

    FeeTier public defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    FeeTier[] private _feeTiers;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public WETH;
    address public migration;
    address public burnAddress;

    uint256 public numTokensToCollectETH;
    uint256 public numOfETHToSwapAndEvolve;

    uint256 public maxTxAmount;

    uint256 private _rTotalExcluded;
    uint256 private _tTotalExcluded;

    uint8 private _decimals;

    bool public inSwapAndLiquify;
    bool private _upgraded;

    bool public swapAndEvolveEnabled;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier lockUpgrade() {
        require(!_upgraded, "ReflectionToken: Already upgraded");
        _;
        _upgraded = true;
    }

    modifier checkTierIndex(uint256 _index) {
        require(_feeTiers.length > _index, "ReflectionToken: Invalid tier index");
        _;
    }

    modifier preventBlacklisted(address _account, string memory errorMsg) {
        require(!_isBlacklisted[_account], errorMsg);
        _;
    }

    modifier isRouter(address _sender,address _receiver) {
        {
            // BUY TX: when router is the receiver
            uint32 size;
            assembly {
                size := extcodesize(_sender)
            }
            if (size > 0) {
                if (_accountsTier[_sender] == 0) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_sender);
                    try _routerCheck.factory() returns (address factory) {
                        _accountsTier[_sender] = 1;
                        console.log("_sender %s", _sender);
                    } catch {}
                }
            }
        }
        {

            // SELL TX: when router is the receiver
            uint32 size;
            assembly {
                size := extcodesize(_receiver)
            }
            if (size > 0) {
                if (_accountsTier[_receiver] == 0) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_receiver);
                    try _routerCheck.factory() returns (address factory) {
                        _accountsTier[_receiver] = 2;
                        console.log("_receiver %s", _receiver);
                    } catch {}
                }
            }
        }

        _;
    }

    event SwapAndEvolveEnabledUpdated(bool enabled);
    event SwapAndEvolve(uint256 ethSwapped, uint256 tokenReceived, uint256 ethIntoLiquidity);

    constructor(address _router, string memory __name, string memory __symbol) {
        _name = __name;
        _symbol = __symbol;
        _decimals = 9;

        uint tTotal = 111 * 10**6 * 10**9; //111 million
        uint rTotal = (MAX - (MAX % tTotal));

        _tTotal = tTotal;
        _rTotal = rTotal;

        maxFee = 1000;//10 percent

        maxTxAmount = 5 * 10**6 * 10**9; //5 million

        burnAddress = 0x000000000000000000000000000000000000dEaD;

        address ownerAddress = owner();
        _rOwned[ownerAddress] = rTotal;

        uniswapV2Router = IUniswapV2Router02(_router);
        WETH = uniswapV2Router.WETH();
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), WETH);
    
        //exclude owner and this contract from fee
        _isExcludedFromFee[ownerAddress] = true;
        _isExcludedFromFee[address(this)] = true; 


        // init _feeTiers

        //no fee on transfers
        // developmentFee, taxFee, staffFee, marketingFee, liquidityFee, developmentWallet, staffWallet
        defaultFees = _addTier(0, 0, 0, 0, 0, address(0), address(0), address(0));
        /// BUY TIER ~800(8%)
        // developmentFee, taxFee, staffFee, marketingFee, liquidityFee, developmentWallet, staffWallet
        _addTier(100, 100, 300, 300, 0, address(0), address(0), address(0)); 
        //SELL TIER ~1000(10%)
        // developmentFee, taxFee, staffFee, marketingFee, liquidityFee, developmentWallet, staffWallet
        _addTier(200, 100, 300, 400, 0, address(0), address(0), address(0));

        emit Transfer(address(0), msg.sender, tTotal);
    }

    // IERC20 functions

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender] - amount
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        require(_allowances[msg.sender][spender] >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] - subtractedValue
        );
        return true;
    }

    // Reflection functions

    function migrate(address account, uint256 amount)
    external
    override
    preventBlacklisted(account, "ReflectionToken: Migrated account is blacklisted")
    {
        require(migration != address(0), "ReflectionToken: Migration is not started");
        require(msg.sender == migration, "ReflectionToken: Not Allowed");
        _migrate(account, amount);
    }

    // onlyOwner

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function excludeFromReward(address account) external onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        _excludeFromReward(account);
    }

    function _excludeFromReward(address account) private {
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
            _tTotalExcluded = _tTotalExcluded + _tOwned[account];
            _rTotalExcluded = _rTotalExcluded + _rOwned[account];
        }

        _isExcluded[account] = true;
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already included");
        _tTotalExcluded = _tTotalExcluded - _tOwned[account];
        _rTotalExcluded = _rTotalExcluded - _rOwned[account];
        _tOwned[account] = 0;
        _isExcluded[account] = false;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function whitelistAddress(address _account, uint256 _tierIndex)
    public
    onlyOwner
    checkTierIndex(_tierIndex)
    preventBlacklisted(_account, "ReflectionToken: Selected account is in blacklist")
    {
        require(_account != address(0), "ReflectionToken: Invalid address");
        _accountsTier[_account] = _tierIndex;
    }

    function excludeWhitelistedAddress(address _account) public onlyOwner {
        require(_account != address(0), "ReflectionToken: Invalid address");
        require(_accountsTier[_account] > 0, "ReflectionToken: Account is not in whitelist");
        _accountsTier[_account] = 0;
    }

    function blacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = true;
        _accountsTier[account] = 0;
    }

    function unBlacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = false;
    }

    // functions for setting fees

    function setDevelopmentFeePercent(uint256 _tierIndex, uint256 _developmentFee)
    external
    onlyOwner
    checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = _feeTiers[_tierIndex];
        _checkFeesChanged(tier, tier.developmentFee, _developmentFee);
        _feeTiers[_tierIndex].developmentFee = _developmentFee;
        if (_tierIndex == 0) {
            defaultFees.developmentFee = _developmentFee;
        }
    }

    function setLiquidityFeePercent(uint256 _tierIndex, uint256 _liquidityFee)
    external
    onlyOwner
    checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = _feeTiers[_tierIndex];
        _checkFeesChanged(tier, tier.liquidityFee, _liquidityFee);
        _feeTiers[_tierIndex].liquidityFee = _liquidityFee;
        if (_tierIndex == 0) {
            defaultFees.liquidityFee = _liquidityFee;
        }
    }

    function setTaxFeePercent(uint256 _tierIndex, uint256 _taxFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = _feeTiers[_tierIndex];
        _checkFeesChanged(tier, tier.taxFee, _taxFee);
        _feeTiers[_tierIndex].taxFee = _taxFee;
        if (_tierIndex == 0) {
            defaultFees.taxFee = _taxFee;
        }
    }

    function setStaffFeePercent(uint256 _tierIndex, uint256 _staffFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = _feeTiers[_tierIndex];
        _checkFeesChanged(tier, tier.staffFee, _staffFee);
        _feeTiers[_tierIndex].staffFee = _staffFee;
        if (_tierIndex == 0) {
            defaultFees.staffFee = _staffFee;
        }
    }

    function setMarketingPercent(uint256 _tierIndex, uint256 _marketingFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = _feeTiers[_tierIndex];
        _checkFeesChanged(tier, tier.marketingFee, _marketingFee);
        _feeTiers[_tierIndex].marketingFee = _marketingFee;
        if (_tierIndex == 0) {
            defaultFees.marketingFee = _marketingFee;
        }
    }

    function setDevelopmentWallet(uint256 _tierIndex, address _developmentWallet)
    external
    onlyOwner
    checkTierIndex(_tierIndex)
    {
        require(_developmentWallet != address(0), "ReflectionToken: Address Zero is not allowed");
        if (!_isExcluded[_developmentWallet]) _excludeFromReward(_developmentWallet);
        _feeTiers[_tierIndex].developmentWallet = _developmentWallet;
        if (_tierIndex == 0) {
            defaultFees.developmentWallet = _developmentWallet;
        }
    }

    function setStaffWallet(uint256 _tierIndex, address _staffWallet) external onlyOwner checkTierIndex(_tierIndex) {
        require(_staffWallet != address(0), "ReflectionToken: Address Zero is not allowed");
        if (!_isExcluded[_staffWallet]) _excludeFromReward(_staffWallet);
        _feeTiers[_tierIndex].staffWallet = _staffWallet;
        if (_tierIndex == 0) {
            defaultFees.staffWallet = _staffWallet;
        }
    }
    function setMarketingWallet(uint256 _tierIndex, address _marketingFeeWallet) external onlyOwner checkTierIndex(_tierIndex) {
        require(_marketingFeeWallet != address(0), "ReflectionToken: Address Zero is not allowed");
        if (!_isExcluded[_marketingFeeWallet]) _excludeFromReward(_marketingFeeWallet);
        _feeTiers[_tierIndex].marketingWallet = _marketingFeeWallet;
        if (_tierIndex == 0) {
            defaultFees.marketingWallet = _marketingFeeWallet;
        }
    }

    function addTier(
        uint256 _developmentFee,
        uint256 _taxFee,
        uint256 _staffFee,
        uint256 _marketingFee,
        uint256 _liquidityFee,
        address _developmentWallet,
        address _staffWallet,
        address _marketingWallet
    ) public onlyOwner {
        _addTier(_developmentFee, _taxFee, _staffFee, _marketingFee,_liquidityFee, _developmentWallet, _staffWallet, _marketingWallet);
    }

    // functions related to uniswap

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        maxTxAmount = _tTotal * maxTxPercent / (10**4);
    }

    function setDefaultSettings() external onlyOwner {
        swapAndEvolveEnabled = true;
    }

    function setSwapAndEvolveEnabled(bool _enabled) public onlyOwner {
        swapAndEvolveEnabled = _enabled;
        emit SwapAndEvolveEnabledUpdated(_enabled);
    }

    function updateRouterAndPair(address _uniswapV2Router, address _uniswapV2Pair) public onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV2Pair = _uniswapV2Pair;
        WETH = uniswapV2Router.WETH();
    }
 
    function swapAndEvolve() public onlyOwner lockTheSwap {
        // split the contract balance into halves
        uint256 contractETHBalance = address(this).balance;
        require(contractETHBalance >= numOfETHToSwapAndEvolve, "ETH balance is not reach for S&E Threshold");

        contractETHBalance = numOfETHToSwapAndEvolve;

        uint256 half = contractETHBalance / 2;
        uint256 otherHalf = contractETHBalance - half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = IReflectionToken(address(this)).balanceOf(msg.sender);
        // swap ETH for Tokens
        _swapETHForTokens(half);

        // how much ETH did we just swap into?
        uint256 newBalance = IReflectionToken(address(this)).balanceOf(msg.sender);
        uint256 swapeedToken = newBalance - initialBalance;

        _approve(msg.sender, address(this), swapeedToken);
        require(IReflectionToken(address(this)).transferFrom(msg.sender, address(this), swapeedToken), "transferFrom is failed");
        // add liquidity to uniswap
        _addLiquidity(swapeedToken, otherHalf);
        emit SwapAndEvolve(half, swapeedToken, otherHalf);
    }

    // update some addresses

    function setMigrationAddress(address _migration) public onlyOwner {
        migration = _migration;
    }

    function updateBurnAddress(address _newBurnAddress) external onlyOwner {
        burnAddress = _newBurnAddress;
        if (!_isExcluded[_newBurnAddress]) {
            _excludeFromReward(_newBurnAddress);
        }
    }

    function setNumberOfTokenToCollectETH(uint256 _numToken) public onlyOwner {
        numTokensToCollectETH = _numToken;
    }

    function setNumOfETHToSwapAndEvolve(uint256 _numETH) public onlyOwner {
        numOfETHToSwapAndEvolve = _numETH;
    }

    // withdraw functions

    function withdrawToken(address _token, uint256 _amount) public onlyOwner {
        require(IReflectionToken(_token).transfer(msg.sender, _amount), "transfer is failed");
    }

    function withdrawETH(uint256 _amount) public onlyOwner {
        (bool sent, ) = payable(msg.sender).call{value: (_amount)}("");
        require(sent, "transfer is failed");
    }

    // internal or private

    function _addTier(
        uint256 _developmentFee,
        uint256 _taxFee,
        uint256 _staffFee,
        uint256 _marketingFee,
        uint256 _liquidityFee,
        address _developmentWallet,
        address _staffWallet,
        address _marketingWallet
    ) internal returns (FeeTier memory) {
        FeeTier memory _newTier = _checkFees(
            FeeTier(_developmentFee, _taxFee, _staffFee, _marketingFee, _liquidityFee, _developmentWallet, _staffWallet, _marketingWallet)
        );
        if (!_isExcluded[_developmentWallet]) _excludeFromReward(_developmentWallet);
        if (!_isExcluded[_staffWallet]) _excludeFromReward(_staffWallet);
        if (!_isExcluded[_marketingWallet]) _excludeFromReward(_marketingWallet);
        _feeTiers.push(_newTier);

        return _newTier;
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _removeAllFee() private {
        _previousFees = _feeTiers[0];
        _feeTiers[0] = _emptyFees;
    }

    function _restoreAllFee() private {
        _feeTiers[0] = _previousFees;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
    private
    preventBlacklisted(owner, "ReflectionToken: Owner address is blacklisted")
    preventBlacklisted(spender, "ReflectionToken: Spender address is blacklisted")
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
    private
    preventBlacklisted(msg.sender, "ReflectionToken: Address is blacklisted")
    preventBlacklisted(from, "ReflectionToken: From address is blacklisted")
    preventBlacklisted(to, "ReflectionToken: To address is blacklisted")
    isRouter(msg.sender, to)
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner())
            require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= maxTxAmount) {
            contractTokenBalance = maxTxAmount;
        }
        bool overMinTokenBalance = contractTokenBalance >= numTokensToCollectETH;
        if (overMinTokenBalance && !inSwapAndLiquify && from != uniswapV2Pair && swapAndEvolveEnabled) {
            contractTokenBalance = numTokensToCollectETH;
            _collectETH(contractTokenBalance);
        }
        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {

            takeFee = false;
        }
        uint256 tierIndex = 0;

        address _from = from;
        address _to = to;
        uint _amount = amount;

         if (takeFee) {
            //for other dapps
            tierIndex = _accountsTier[_from];

            if (msg.sender != _from) {
                tierIndex = _accountsTier[msg.sender];
            }
        }
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(_from, _to, _amount, tierIndex, takeFee);
    }

    function _collectETH(uint256 contractTokenBalance) private lockTheSwap {
        _swapTokensForETH(contractTokenBalance);
    }

    function _swapTokensForETH(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapETHForTokens(uint256 ethAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        _approve(owner(), address(uniswapV2Router), ethAmount);
        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: ethAmount }(
            0, // accept any amount of Token
            path,
            owner(),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }


    //TODO: remove
    //swap functions

    function addLiquidity(uint256 tokenAmount) public payable {
        
        require(IReflectionToken(address(this)).transferFrom(msg.sender, address(this), tokenAmount), "transferFrom is failed");
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        //assuming apprive has been called by owner() on the client
        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: msg.value }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }
    function buyTokens() public payable {
         // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        // _approve(owner(), address(uniswapV2Router), msg.value);
        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: msg.value }(
            0, // accept any amount of Token
            path,
            msg.sender,
            block.timestamp
        );
    }

    function sellTokens(uint256 tokenAmount) public  {
// generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        require(IReflectionToken(address(this)).transferFrom(msg.sender, address(this), tokenAmount), "transferFrom is failed");

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            msg.sender,
            block.timestamp
        );    
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        uint256 tierIndex,
        bool takeFee
    ) private {
        if (!takeFee) _removeAllFee();

        if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount, tierIndex);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount, tierIndex);
        }

        if (!takeFee) _restoreAllFee();
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - _values.rAmount;
        _tOwned[recipient] = _tOwned[recipient] + _values.tTransferAmount;
        _rOwned[recipient] = _rOwned[recipient] + _values.rTransferAmount;

        _tTotalExcluded = _tTotalExcluded + _values.tTransferAmount - tAmount;
        _rTotalExcluded = _rTotalExcluded + _values.rTransferAmount - _values.rAmount;

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender] - _values.rAmount;
        _rOwned[recipient] = _rOwned[recipient] + _values.rTransferAmount;
        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender] - _values.rAmount;
        _tOwned[recipient] = _tOwned[recipient] + _values.tTransferAmount;
        _rOwned[recipient] = _rOwned[recipient] + _values.rTransferAmount;

        _tTotalExcluded = _tTotalExcluded + _values.tTransferAmount;
        _rTotalExcluded = _rTotalExcluded + _values.rTransferAmount;

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - _values.rAmount;
        _rOwned[recipient] = _rOwned[recipient] + _values.rTransferAmount;
        _tTotalExcluded = _tTotalExcluded - tAmount;
        _rTotalExcluded = _rTotalExcluded - _values.rAmount;

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _takeFees(
        address sender,
        FeeValues memory values,
        uint256 tierIndex
    ) private {
        _takeFee(sender, values.tLiquidity, address(this));
        _takeFee(sender, values.tDevelopment, _feeTiers[tierIndex].developmentWallet);
        _takeFee(sender, values.tMarketing, _feeTiers[tierIndex].marketingWallet);
        _takeFee(sender, values.tStaff, _feeTiers[tierIndex].staffWallet);

    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeFee(
        address sender,
        uint256 tAmount,
        address recipient
    ) private {
        if (recipient == address(0)) return;
        if (tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount * currentRate;
        _rOwned[recipient] = _rOwned[recipient] + rAmount;
    
        if (_isExcluded[recipient]) {
            _tOwned[recipient] = _tOwned[recipient] + tAmount;
            _tTotalExcluded = _tTotalExcluded + tAmount;
            _rTotalExcluded = _rTotalExcluded + rAmount;
        }

        emit Transfer(sender, recipient, tAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeBurn(address sender, uint256 _amount) private {
        if (_amount == 0) return;
        address _burnAddress = burnAddress;
        _tOwned[_burnAddress] = _tOwned[_burnAddress] + _amount;
        if (_isExcluded[_burnAddress]) {
            _tTotalExcluded = _tTotalExcluded + _amount;
        }

        emit Transfer(sender, _burnAddress, _amount);
    }

    function _migrate(address account, uint256 amount) private {
        require(account != address(0), "ERC20: mint to the zero address");

        _tokenTransfer(owner(), account, amount, 0, false);
    }

    // Reflection - Read functions

    // external or public

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function reflectionFromTokenInTiers(
        uint256 tAmount,
        uint256 _tierIndex,
        bool deductTransferFee
    ) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rAmount;
        } else {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rTransferAmount;
        }
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns (uint256) {
        return reflectionFromTokenInTiers(tAmount, 0, deductTransferFee);
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function accountTier(address _account) public view returns (FeeTier memory) {
        return _feeTiers[_accountsTier[_account]];
    }

    function feeTier(uint256 _tierIndex) public view checkTierIndex(_tierIndex) returns (FeeTier memory) {
        return _feeTiers[_tierIndex];
    }

    function feeTiersLength() public view returns (uint256) {
        return _feeTiers.length;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _accountsTier[_account] > 0;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _isBlacklisted[account];
    }

    function isMigrationStarted() external view override returns (bool) {
        return migration != address(0);
    }

    function getContractBalance() public view returns (uint256) {
        return balanceOf(address(this));
    }

    function getETHBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // internal or private

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        if (_rTotalExcluded > _rTotal || _tTotalExcluded > _tTotal) {
            return (_rTotal, _tTotal);
        }
        uint256 rSupply = _rTotal - _rTotalExcluded;
        uint256 tSupply = _tTotal - _tTotalExcluded;

        //if total of non staking accounts exceed that of staking accounts, 
        //use  (_rTotal, _tTotal) as rSupply will be really small
        //else use (rSupply, tSupply)
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);

        return (rSupply, tSupply);
    }

    function _calculateFee(uint256 _amount, uint256 _fee) private pure returns (uint256) {
        if (_fee == 0) return 0;
        return _amount * _fee / (10**4);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tTransferFee,
        uint256 currentRate
    )
    private
    pure
    returns (
        uint256,
        uint256,
        uint256
    )
    {
        uint256 rAmount = tAmount * currentRate;
        uint256 rFee = tFee * currentRate;
        uint256 rTransferFee = tTransferFee * currentRate;
        uint256 rTransferAmount = rAmount - rFee - rTransferFee;
        return (rAmount, rTransferAmount, rFee);
    }

    function _getValues(uint256 tAmount, uint256 _tierIndex) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _tierIndex);
        uint256 tTransferFee = tValues.tDevelopment + tValues.tLiquidity + tValues.tStaff + tValues.tMarketing;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tValues.tFee,
            tTransferFee,
            _getRate()
        );
        return
        FeeValues(
            rAmount,
            rTransferAmount,
            rFee,
            tValues.tTransferAmount,
            tValues.tDevelopment,
            tValues.tLiquidity,
            tValues.tFee,
            tValues.tStaff,
            tValues.tMarketing
        );
    }

    function _getTValues(uint256 tAmount, uint256 _tierIndex) private view returns (tFeeValues memory) {
        FeeTier memory tier = _feeTiers[_tierIndex];
        tFeeValues memory tValues = tFeeValues(
            0,
            _calculateFee(tAmount, tier.developmentFee),
            _calculateFee(tAmount, tier.liquidityFee),
            _calculateFee(tAmount, tier.taxFee),
            _calculateFee(tAmount, tier.staffFee),
            _calculateFee(tAmount, tier.marketingFee)
        );

        tValues.tTransferAmount = tAmount - tValues.tDevelopment - tValues.tLiquidity - tValues.tFee - tValues.tStaff - tValues.tMarketing;

        return tValues;
    }

    function _checkFees(FeeTier memory _tier) internal view returns (FeeTier memory) {
        uint256 _fees = _tier.developmentFee + _tier.liquidityFee + _tier.taxFee + _tier.staffFee + _tier.marketingFee;
        require(_fees <= maxFee, "ReflectionToken: Fees exceeded max limitation");

        return _tier;
    }

    function _checkFeesChanged(
        FeeTier memory _tier,
        uint256 _oldFee,
        uint256 _newFee
    ) internal view {
        uint256 _fees = _tier.developmentFee + _tier.liquidityFee + _tier.taxFee + _tier.staffFee + _tier.marketingFee - _oldFee + _newFee;

        require(_fees <= maxFee, "ReflectionToken: Fees exceeded max limitation");
    }

    //to receive ETH from uniswapV2Router when swapping
    receive() external payable {}
}
