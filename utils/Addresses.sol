// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

library Addresses {
    address public constant ADMIN_MULTISIG = 0x13014e6d083799F2e88a3a0d72c074CB578741F2;

    address public constant ADMIN_ROLE = ADMIN_MULTISIG;
    address public constant MANAGER_ROLE = ADMIN_MULTISIG;
    address public constant OPERATOR_ROLE = ADMIN_MULTISIG;

    address public constant PROXY_OWNER = ADMIN_MULTISIG;
    address public constant PROXY_FACTORY = 0xAeC6F2181fbDc4e41463d030E0bD73A6A08b7E6E;
    address public constant PROXY_ADMIN = 0xf91e0905A65ceD6d350f3034c05e86FFFdA19a2d;

    address public constant ZGETH = 0x17fdeB2fbB8089fea8a7BDb847E49ce67cF863df;

    address public constant LRT_CONFIG = 0x347b65b75Ae5aB97D86032D353aa805c1625fddE;
    address public constant LRT_ORACLE = 0xAa6Fd6788fCA604AcFD3FE7e160Fbfcf4F0ef95C;
    address public constant LRT_DEPOSIT_POOL = 0xBcE1eD62786703fc974774A43dFCfeB609AD3329;
    address public constant NODE_DELEGATOR = 0x09F722CbD51F29DC1FA487857C114766FD48195D;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant EIGEN_UNPAUSER = 0x369e6F597e22EaB55fFb173C6d9cD234BD699111;
    address public constant EIGEN_STRATEGY_MANAGER = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;

    address public constant CONNEXT_DIAMOND = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
    address public constant LINK_ROUTER_CLIENT = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address public constant LINK_TOKEN = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant BRIDGE = 0x7919A673AD97E52260e86468398F6219E1DB1Ffc;

    address public constant OP_LINK_ROUTER_CLIENT = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    address public constant OP_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant OP_NEXT_WETH = 0x2983bf5c334743Aa6657AD70A55041d720d225dB;
    address public constant OP_CONNEXT_DIAMOND = 0xEE9deC2712cCE65174B561151701Bf54b99C24C8;
}
