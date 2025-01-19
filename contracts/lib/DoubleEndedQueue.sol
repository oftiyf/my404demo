// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (最后更新 v5.0.0) (utils/structs/DoubleEndedQueue.sol)
// 由 Pandora Labs 修改以支持原生 uint256 操作
pragma solidity ^0.8.20;

/**
 * @dev 一个序列数据结构,可以在序列的两端(称为前端和后端)高效地进行推入和弹出操作(即插入和删除)。
 * 除了其他访问模式外,它可以用于实现高效的 LIFO 和 FIFO 队列。存储使用经过优化,所有操作都是 O(1) 常数时间。
 * 这包括 {clear} 操作,因为现有的队列内容会保留在存储中。
 *
 * 该结构体称为 `Uint256Deque`。这个数据结构只能在存储中使用,不能在内存中使用。
 *
 * ```solidity
 * DoubleEndedQueue.Uint256Deque queue;
 * ```
 */
library DoubleEndedQueue {
  /**
   * @dev 由于队列为空,操作(例如 {front})无法完成。
   */
  error QueueEmpty();

  /**
   * @dev 由于队列已满,推入操作无法完成。
   */
  error QueueFull();

  /**
   * @dev 由于索引超出范围,操作(例如 {at})无法完成。
   */
  error QueueOutOfBounds();

  /**
   * @dev 索引为 128 位,因此开始和结束被打包在单个存储槽中以实现高效访问。
   *
   * 结构体成员带有下划线前缀,表示它们是"私有的",不应直接读取或写入。
   * 请使用下面提供的函数。手动修改结构体可能会违反假设并导致意外行为。
   *
   * 第一个元素在 data[begin],最后一个元素在 data[end - 1]。这个范围可以环绕。
   */
  struct Uint256Deque {
    uint128 _begin;
    uint128 _end;
    mapping(uint128 index => uint256) _data;
  }

  /**
   * @dev 在队列末尾插入一个元素。
   *
   * 如果队列已满,则回退并抛出 {QueueFull}。
   */
  function pushBack(Uint256Deque storage deque, uint256 value) internal {
    unchecked {
      uint128 backIndex = deque._end;
      if (backIndex + 1 == deque._begin) revert QueueFull();
      deque._data[backIndex] = value;
      deque._end = backIndex + 1;
    }
  }

  /**
   * @dev 移除队列末尾的元素并返回它。
   *
   * 如果队列为空,则回退并抛出 {QueueEmpty}。
   */
  function popBack(
    Uint256Deque storage deque
  ) internal returns (uint256 value) {
    unchecked {
      uint128 backIndex = deque._end;
      if (backIndex == deque._begin) revert QueueEmpty();
      --backIndex;
      value = deque._data[backIndex];
      delete deque._data[backIndex];
      deque._end = backIndex;
    }
  }

  /**
   * @dev 在队列开头插入一个元素。
   *
   * 如果队列已满,则回退并抛出 {QueueFull}。
   */
  function pushFront(Uint256Deque storage deque, uint256 value) internal {
    unchecked {
      uint128 frontIndex = deque._begin - 1;
      if (frontIndex == deque._end) revert QueueFull();
      deque._data[frontIndex] = value;
      deque._begin = frontIndex;
    }
  }

  /**
   * @dev 移除队列开头的元素并返回它。
   *
   * 如果队列为空,则回退并抛出 `QueueEmpty`。
   */
  function popFront(
    Uint256Deque storage deque
  ) internal returns (uint256 value) {
    unchecked {
      uint128 frontIndex = deque._begin;
      if (frontIndex == deque._end) revert QueueEmpty();
      value = deque._data[frontIndex];
      delete deque._data[frontIndex];
      deque._begin = frontIndex + 1;
    }
  }

  /**
   * @dev 返回队列开头的元素。
   *
   * 如果队列为空,则回退并抛出 `QueueEmpty`。
   */
  function front(
    Uint256Deque storage deque
  ) internal view returns (uint256 value) {
    if (empty(deque)) revert QueueEmpty();
    return deque._data[deque._begin];
  }

  /**
   * @dev 返回队列末尾的元素。
   *
   * 如果队列为空,则回退并抛出 `QueueEmpty`。
   */
  function back(
    Uint256Deque storage deque
  ) internal view returns (uint256 value) {
    if (empty(deque)) revert QueueEmpty();
    unchecked {
      return deque._data[deque._end - 1];
    }
  }

  /**
   * @dev 返回队列中由 `index` 给定位置的元素,第一个元素的索引为 0,最后一个元素的索引为 `length(deque) - 1`。
   *
   * 如果索引超出范围,则回退并抛出 `QueueOutOfBounds`。
   */
  function at(
    Uint256Deque storage deque,
    uint256 index
  ) internal view returns (uint256 value) {
    if (index >= length(deque)) revert QueueOutOfBounds();
    // 根据构造,length 是一个 uint128,因此上面的检查确保 index 可以安全地向下转换为 uint128
    unchecked {
      return deque._data[deque._begin + uint128(index)];
    }
  }

  /**
   * @dev 将队列重置为空。
   *
   * 注意:当前的元素会保留在存储中。这不会影响队列的功能,但会错过潜在的 gas 退款。
   */
  function clear(Uint256Deque storage deque) internal {
    deque._begin = 0;
    deque._end = 0;
  }

  /**
   * @dev 返回队列中的元素数量。
   */
  function length(Uint256Deque storage deque) internal view returns (uint256) {
    unchecked {
      return uint256(deque._end - deque._begin);
    }
  }

  /**
   * @dev 如果队列为空则返回 true。
   */
  function empty(Uint256Deque storage deque) internal view returns (bool) {
    return deque._end == deque._begin;
  }
}
