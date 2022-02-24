// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/structs/EnumerableMap.sol)

pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @dev Library for managing an enumerable variant of Solidity's
 * https://solidity.readthedocs.io/en/latest/types.html#mapping-types[`mapping`]
 * type.
 *
 * Maps have the following properties:
 *
 * - Entries are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableMap for EnumerableMap.UintToAddressMap;
 *
 *     // Declare a set state variable
 *     EnumerableMap.UintToAddressMap private myMap;
 * }
 * ```
 *
 * As of v3.0.0, only maps of type `uint256 -> address` (`UintToAddressMap`) are
 * supported.
 */
library EnumerableMap {
  using EnumerableSet for EnumerableSet.AddressSet;

  // To implement this library for multiple types with as little code
  // repetition as possible, we write it in terms of a generic Map type with
  // bytes32 keys and values.
  // The Map implementation uses private functions, and user-facing
  // implementations (such as Uint256ToAddressMap) are just wrappers around
  // the underlying Map.
  // This means that we can only create new EnumerableMaps for types that fit
  // in bytes32.

  struct AddressToUintsMap {
    // Storage of keys
    EnumerableSet.AddressSet _keys;
    mapping(address => uint[2]) _values;
  }

  /**
   * @dev Adds a key-value pair to a map, or updates the value for an existing
   * key. O(1).
   *
   * Returns true if the key was added to the map, that is if it was not
   * already present.
   */
  function set(
    AddressToUintsMap storage map,
    address key,
    uint[2] memory value
  ) internal returns (bool) {
    map._values[key] = value;
    return map._keys.add(key);
  }

  /**
   * @dev Removes a key-value pair from a map. O(1).
   *
   * Returns true if the key was removed from the map, that is if it was present.
   */
  function remove(AddressToUintsMap storage map, address key)
    internal
    returns (bool)
  {
    delete map._values[key];
    return map._keys.remove(key);
  }

  /**
   * @dev Returns true if the key is in the map. O(1).
   */
  function contains(AddressToUintsMap storage map, address key)
    internal
    view
    returns (bool)
  {
    return map._keys.contains(key);
  }

  /**
   * @dev Returns the number of key-value pairs in the map. O(1).
   */
  function length(AddressToUintsMap storage map)
    internal
    view
    returns (uint256)
  {
    return map._keys.length();
  }

  /**
   * @dev Returns the key-value pair stored at position `index` in the map. O(1).
   *
   * Note that there are no guarantees on the ordering of entries inside the
   * array, and it may change when more entries are added or removed.
   *
   * Requirements:
   *
   * - `index` must be strictly less than {length}.
   */
  function at(AddressToUintsMap storage map, uint256 index)
    internal
    view
    returns (address, uint[2] memory)
  {
    address key = map._keys.at(index);
    return (key, map._values[key]);
  }

  /**
   * @dev Returns the value associated with `key`.  O(1).
   *
   * Requirements:
   *
   * - `key` must be in the map.
   */
  function get(AddressToUintsMap storage map, address key)
    private
    view
    returns (uint[2] memory)
  {
    uint[2] memory value = map._values[key];
    require(contains(map, key), "EnumerableMap: nonexistent key");
    return value;
  }
}
