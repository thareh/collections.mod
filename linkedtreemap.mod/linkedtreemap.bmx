SuperStrict

Rem
bbdoc: Collections/LinkedTreeMap
End Rem
Module Collections.LinkedTreeMap

Import Collections.IMap
Import Collections.Errors
Import Collections.ImmutableList

Rem
bbdoc: A tree map that maintains insertion order or access order of its entries.
about: This is a red-black tree map implementation that also maintains a doubly-linked
list of its entries to preserve insertion order or access order (for LRU caching).
Lookups remain ordered by key (via the tree); iteration follows the linked list order.
It supports optional maximum size with automatic eviction of least-recently-used
(or oldest) entries.
End Rem
Type TLinkedTreeMap<K, V> Implements IMap<K, V>

	Internal
	Field root:TLinkedTreeMapNode<K,V>
	Field size:Int
	Field _version:Int
	Field comparator:IComparator<K>

	' insertion / access order list
	Field _head:TLinkedTreeMapNode<K,V>
	Field _tail:TLinkedTreeMapNode<K,V>

	' options for lru and fifo eviction
	Field _accessOrder:Int     ' False=Insertion order (default), True=Access order (LRU)
	Field _maxSize:Int         ' 0 = unbounded; >0 = max entries, evict LRU/FIFO on insert

	Public

	Rem
	bbdoc: Creates a new #TLinkedTreeMap using the default comparator.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a new #TLinkedTreeMap.
	about: @comparator is an optional comparator for the keys.
	If @accessOrder is #True, the map maintains access order (LRU) instead of insertion order.
	If @maxSize is greater than 0, the map will either evict least-recently-used entries when
	the size exceeds maxSize, or if @accessOrder is #False (the default), evict oldest entries (FIFO).
	End Rem
	Method New(comparator:IComparator<K>, accessOrder:Int = False, maxSize:Int = 0)
		Self.comparator = comparator
		_accessOrder = accessOrder
		_maxSize = maxSize
	End Method

	Rem
	bbdoc: Creates a new #TLinkedTreeMap with access-order / max-size options only.
	End Rem
	Method New(accessOrder:Int, maxSize:Int = 0)
		_accessOrder = accessOrder
		_maxSize = maxSize
	End Method

	Method Count:Int() Override
		Return size
	End Method

	Method IsEmpty:Int() Override
		Return size = 0
	End Method

	Method Clear() Override
		root = Null
		size = 0
		_head = Null
		_tail = Null
		_version :+ 1
	End Method

	Method GetIterator:IIterator<IMapNode<K,V>>()
		Return New TLinkedTreeMapIterator<K,V>(Self)
	End Method

	Method Keys:ICollection<K>() Override
		If size = 0 Then
			Return New TEmptyImmutableList<K>
		End If
		Return New TLinkedTreeMapKeysView<K,V>(Self)
	End Method

	Method Values:ICollection<V>() Override
		If size = 0 Then
			Return New TEmptyImmutableList<V>
		End If
		Return New TLinkedTreeMapValuesView<K,V>(Self)
	End Method

	Method CopyTo(array:IMapNode<K,V>[], index:Int = 0)
		Local i:Int = index
		Local n:TLinkedTreeMapNode<K,V> = _head
		While n
			array[i] = n
			i :+ 1
			n = n._next
		Wend
	End Method

	Method Add(key:K, value:V) Override
		If FindNode(key) Then
			Throw New TArgumentException("An element with the same key already exists in the map")
		End If
		_AddNew(key, value)
	End Method

	Method Put:V(key:K, value:V) Override
		Local node:TLinkedTreeMapNode<K,V> = FindNode(key)
		If node Then
			Local oldValue:V = node.value
			node.value = value
			If Not Touch(node) Then
				_version :+ 1
			End If
			Return oldValue
		End If

		_AddNew(key, value)
		Local def:V
		Return def
	End Method

	Method ContainsKey:Int(key:K) Override
		Return FindNode(key) <> Null
	End Method

	Method TryGetValue:Int(key:K, value:V Var)
		Local node:TLinkedTreeMapNode<K,V> = FindNode(key)
		If node <> Null Then
			value = node.value
			Touch(node)
			Return True
		End If
		Return False
	End Method

	Method Operator [] :V(key:K)
		Local node:TLinkedTreeMapNode<K,V> = FindNode(key)
		If node Then
			Local v:V = node.value
			Touch(node)
			Return v
		End If
		Local def:V
		Return def
	End Method

	Method Operator []= (key:K, value:V)
		Put(key, value)
	End Method

	Method Remove:Int(key:K) Override
		Local node:TLinkedTreeMapNode<K,V> = FindNode(key)
		If node = Null Then
			Return False
		End If
		Unlink(node)
		RemoveNode(node)
		size :- 1
		_version :+ 1
		Return True
	End Method

	Method ContainsValue:Int(value:V)
		Local n:TLinkedTreeMapNode<K,V> = _head
		While n
			If n.value = value Then
				Return True
			End If
			n = n._next
		Wend
		Return False
	End Method

	Rem
	bbdoc: Sets the maximum size of the map. If the current size exceeds maxSize,
	the least-recently-used (or oldest) entries will be evicted.
	about: A maxSize of 0 means the map is unbounded.
	End Rem
	Method SetMaxSize(maxSize:Int)
		_maxSize = maxSize
		EvictIfNeeded()
	End Method

	' -----------------------
	' Internals
	' -----------------------
	Private

	Method CompareKeys:Int(a:K, b:K)
		If comparator Then
			Return comparator.Compare(a, b)
		End If
		Return DefaultComparator_Compare(a, b)
	End Method

	Method LinkLast(e:TLinkedTreeMapNode<K,V>)
		e._prev = _tail
		e._next = Null
		If _tail Then
			_tail._next = e
		Else
			_head = e
		End If
		_tail = e
	End Method

	Method Unlink(e:TLinkedTreeMapNode<K,V>)
		Local p:TLinkedTreeMapNode<K,V> = e._prev
		Local n:TLinkedTreeMapNode<K,V> = e._next

		If p Then
			p._next = n
		Else
			_head = n
		End If

		If n Then
			n._prev = p
		Else
			_tail = p
		End If

		e._prev = Null
		e._next = Null
	End Method

	Method Touch:Int(entry:TLinkedTreeMapNode<K,V>)
		' Only when access-order mode is enabled and entry isn't already the tail
		If Not _accessOrder Then
			Return False
		End If
		If entry = Null Or entry = _tail Then
			Return False
		End If
		Unlink(entry)
		LinkLast(entry)
		_version :+ 1
		Return True
	End Method

	Method EvictIfNeeded()
		If _maxSize <= 0 Then Return
		While size > _maxSize And _head
			Local k:K = _head.key
			Remove(k)
		Wend
	End Method

	Method _AddNew(key:K, value:V)
		Local node:TLinkedTreeMapNode<K,V> = root
		Local parent:TLinkedTreeMapNode<K,V>
		Local cmp:Int

		While node <> Null
			parent = node
			cmp = CompareKeys(key, node.key)
			If cmp < 0 Then
				node = node.leftNode
			Else If cmp > 0 Then
				node = node.rightNode
			Else
				' should not happen (caller checks)
				node.value = value
				Return
			End If
		Wend

		node = New TLinkedTreeMapNode<K,V>
		node.key = key
		node.value = value
		node.colour = 0
		node.parent = parent
		node._map = Self

		size :+ 1
		LinkLast(node)

		If parent = Null
			root = node
		Else If cmp > 0 Then
			parent.rightNode = node
		Else
			parent.leftNode = node
		End If

		RepairAdd(node)
		_version :+ 1
		EvictIfNeeded()
	End Method

	Method FindNode:TLinkedTreeMapNode<K,V>(key:K)
		Local node:TLinkedTreeMapNode<K,V> = root
		While node <> Null
			Local cmp:Int = CompareKeys(key, node.key)
			If cmp > 0 Then
				node = node.rightNode
			Else If cmp < 0 Then
				node = node.leftNode
			Else
				Return node
			End If
		Wend
		Return Null
	End Method

	Method FirstNode:TLinkedTreeMapNode<K,V>()
		' Tree-order first (smallest key) – kept for completeness; iteration uses _head
		Local node:TLinkedTreeMapNode<K,V> = root
		While node <> Null And node.leftNode <> Null
			node = node.leftNode
		Wend
		Return node
	End Method

	Method RotateLeft(node:TLinkedTreeMapNode<K,V>)
		Local child:TLinkedTreeMapNode<K,V> = node.rightNode
		node.rightNode = child.leftNode
		If child.leftNode <> Null
			child.leftNode.parent = node
		End If
		child.parent = node.parent
		If node.parent <> Null
			If node = node.parent.leftNode
				node.parent.leftNode = child
			Else
				node.parent.rightNode = child
			End If
		Else
			root = child
		End If
		child.leftNode = node
		node.parent = child
	End Method

	Method RotateRight(node:TLinkedTreeMapNode<K,V>)
		Local child:TLinkedTreeMapNode<K,V> = node.leftNode
		node.leftNode = child.rightNode
		If child.rightNode <> Null
			child.rightNode.parent = node
		End If
		child.parent = node.parent
		If node.parent <> Null
			If node = node.parent.rightNode
				node.parent.rightNode = child
			Else
				node.parent.leftNode = child
			End If
		Else
			root = child
		End If
		child.rightNode = node
		node.parent = child
	End Method

	Method RepairAdd(node:TLinkedTreeMapNode<K,V>)
		While node.parent And node.parent.colour = 0 And node.parent.parent <> Null
			If node.parent = node.parent.parent.leftNode Then
				Local uncle:TLinkedTreeMapNode<K,V> = node.parent.parent.rightNode
				If uncle And uncle.colour = 0 Then
					node.parent.colour = 1
					uncle.colour = 1
					uncle.parent.colour = 0
					node = uncle.parent
				Else
					If node = node.parent.rightNode Then
						node = node.parent
						RotateLeft(node)
					End If
					node.parent.colour = 1
					node.parent.parent.colour = 0
					RotateRight(node.parent.parent)
				End If
			Else
				Local uncle:TLinkedTreeMapNode<K,V> = node.parent.parent.leftNode
				If uncle And uncle.colour = 0
					node.parent.colour = 1
					uncle.colour = 1
					uncle.parent.colour = 0
					node = uncle.parent
				Else
					If node = node.parent.leftNode Then
						node = node.parent
						RotateRight(node)
					End If
					node.parent.colour = 1
					node.parent.parent.colour = 0
					RotateLeft(node.parent.parent)
				End If
			End If
		Wend
		root.colour = 1
	End Method

	Method RemoveNode(node:TLinkedTreeMapNode<K,V>)
		' node has already been unlinked from the order list by the caller.
		' We must remove it from the tree without disturbing the list positions
		' of any surviving nodes. When the node has two children we therefore
		' transplant the successor *node object* into node's tree position
		' (rather than copying key/value), so the successor keeps its list links.

		Local splice:TLinkedTreeMapNode<K,V>
		Local child:TLinkedTreeMapNode<K,V>

		If node.leftNode = Null Then
			splice = node
			child = node.rightNode
		Else If node.rightNode = Null Then
			splice = node
			child = node.leftNode
		Else
			' Find in-order successor
			Local successor:TLinkedTreeMapNode<K,V> = node.rightNode
			While successor.leftNode <> Null
				successor = successor.leftNode
			Wend

			' successor will take node's place in the tree; it keeps its own
			' list links (already correct).
			Local succParent:TLinkedTreeMapNode<K,V> = successor.parent
			Local succChild:TLinkedTreeMapNode<K,V> = successor.rightNode ' successor has no left child
			Local succColour:Int = successor.colour

			If succParent = node Then
				' successor is the direct right child of node.
				' After transplant, successor.rightNode stays as its current right child.
				' Just reparent that child (already succChild) under successor – nothing extra.
			Else
				' Detach successor from its current parent
				If succChild <> Null Then
					succChild.parent = succParent
				End If
				If succParent = Null Then
					root = succChild
				Else If successor = succParent.leftNode Then
					succParent.leftNode = succChild
				Else
					succParent.rightNode = succChild
				End If

				' Attach node's right subtree under successor
				successor.rightNode = node.rightNode
				If node.rightNode <> Null Then
					node.rightNode.parent = successor
				End If
			End If

			' Transplant successor into node's tree position
			successor.parent = node.parent
			successor.leftNode = node.leftNode
			successor.colour = node.colour

			If node.leftNode <> Null Then
				node.leftNode.parent = successor
			End If

			If node.parent = Null Then
				root = successor
			Else If node = node.parent.leftNode Then
				node.parent.leftNode = successor
			Else
				node.parent.rightNode = successor
			End If

			' Fix-up starts from the place where successor was removed
			If succColour = 1 Then
				If succParent = node Then
					RepairRemove(succChild, successor)
				Else
					RepairRemove(succChild, succParent)
				End If
			End If
			Return
		End If

		' 0 or 1 child case
		Local parent:TLinkedTreeMapNode<K,V> = splice.parent
		If child <> Null Then
			child.parent = parent
		End If
		If parent = Null Then
			root = child
			Return
		End If
		If splice = parent.leftNode Then
			parent.leftNode = child
		Else
			parent.rightNode = child
		End If

		If splice.colour = 1 Then
			RepairRemove(child, parent)
		End If
	End Method

	Method RepairRemove(node:TLinkedTreeMapNode<K,V>, parent:TLinkedTreeMapNode<K,V>)

		Function IsBlack:Int(n:TLinkedTreeMapNode<K,V>) Inline
			Return n = Null Or n.colour = 1
		End Function

		Function IsRed:Int(n:TLinkedTreeMapNode<K,V>) Inline
			Return n <> Null And n.colour = 0
		End Function

		While node <> root And (node = Null Or node.colour = 1)
			Local leftBranch:Int = (parent <> Null And node = parent.leftNode)
			Local sib:TLinkedTreeMapNode<K,V> = Null
			If leftBranch Then
				If parent <> Null Then
					sib = parent.rightNode
				End If
			Else
				If parent <> Null Then
					sib = parent.leftNode
				End If
			End If

			If IsRed(sib) Then
				sib.colour = 1
				parent.colour = 0
				If leftBranch Then
					RotateLeft(parent)
					If parent <> Null Then
						sib = parent.rightNode
					End If
				Else
					RotateRight(parent)
					If parent <> Null Then
						sib = parent.leftNode
					End If
				End If
			End If

			Local sibLeft:TLinkedTreeMapNode<K,V> = Null
			Local sibRight:TLinkedTreeMapNode<K,V> = Null
			If sib <> Null Then
				sibLeft = sib.leftNode
				sibRight = sib.rightNode
			End If

			If (leftBranch And IsBlack(sibLeft) And IsBlack(sibRight)) Or (Not leftBranch And IsBlack(sibRight) And IsBlack(sibLeft)) Then
				If sib <> Null Then
					sib.colour = 0
				End If
				node = parent
				If parent <> Null Then
					parent = parent.parent
				End If
			Else
				If leftBranch Then
					If IsBlack(sibRight) Then
						If sibLeft <> Null Then
							sibLeft.colour = 1
						End If
						If sib <> Null Then
							sib.colour = 0
						End If
						If sib <> Null Then
							RotateRight(sib)
						End If
						If parent <> Null Then
							sib = parent.rightNode
						End If
					End If
					If sib <> Null Then
						sib.colour = parent.colour
					End If
					parent.colour = 1
					If sib <> Null And sib.rightNode <> Null Then
						sib.rightNode.colour = 1
					End If
					RotateLeft(parent)
				Else
					If IsBlack(sibLeft) Then
						If sibRight <> Null Then
							sibRight.colour = 1
						End If
						If sib <> Null Then
							sib.colour = 0
						End If
						If sib <> Null Then
							RotateLeft(sib)
						End If
						If parent <> Null Then
							sib = parent.leftNode
						End If
					End If
					If sib <> Null Then
						sib.colour = parent.colour
					End If
					parent.colour = 1
					If sib <> Null And sib.leftNode <> Null Then
						sib.leftNode.colour = 1
					End If
					RotateRight(parent)
				End If
				node = root
			End If
		Wend

		If node <> Null Then
			node.colour = 1
		End If
	End Method

End Type


Rem
bbdoc: A #TLinkedTreeMap node representing a key/value pair.
about: Combines red-black tree structure with doubly-linked list pointers for
insertion / access order.
End Rem
Type TLinkedTreeMapNode<K, V> Implements IMapNode<K,V>

	' red-black tree links
	Field parent:TLinkedTreeMapNode<K,V>
	Field leftNode:TLinkedTreeMapNode<K,V>
	Field rightNode:TLinkedTreeMapNode<K,V>
	Field colour:Int

	Field key:K
	Field value:V

	' doubly-linked insertion / access order
	Field _prev:TLinkedTreeMapNode<K,V>
	Field _next:TLinkedTreeMapNode<K,V>

	Field _map:TLinkedTreeMap<K,V>

	Public

	Method GetKey:K() Override
		Return key
	End Method

	Method GetValue:V() Override
		Return value
	End Method

	Method Deconstruct(keyOut:K Var, valueOut:V Var) Override
		keyOut = key
		valueOut = value
	End Method

	' Iteration follows the linked list (insertion/access order), not tree order.
	Method HasNext:Int() Override
		Return _next <> Null
	End Method

	Method NextNode:IMapNode<K,V>() Override
		Return _next
	End Method

End Type


Type TLinkedTreeMapIterator<K,V> Implements IIterator<IMapNode<K,V>>
	Private
	Field map:TLinkedTreeMap<K,V>
	Field node:TLinkedTreeMapNode<K,V>
	Field started:Int
	Field version:Int

	Public
	Method New(map:TLinkedTreeMap<K,V>)
		Self.map = map
		version = map._version
	End Method

	Method Current:IMapNode<K,V>()
		Return node
	End Method

	Method MoveNext:Int()
		If version <> map._version Then
			Throw New TInvalidOperationException("Collection was modified during iteration")
		End If

		If Not started Then
			started = True
			node = map._head
			Return node <> Null
		End If

		If node Then
			node = node._next
			Return node <> Null
		End If

		Return False
	End Method
End Type


Type TLinkedTreeMapKeysView<K,V> Implements ICollection<K>
	Private
	Field _map:TLinkedTreeMap<K,V>

	Public
	Method New(map:TLinkedTreeMap<K,V>)
		Self._map = map
	End Method

	Method Count:Int()
		Return _map.Count()
	End Method

	Method IsEmpty:Int()
		Return _map.IsEmpty()
	End Method

	Method Clear()
		UnsupportedOperationError()
	End Method

	Method CopyTo(arr:K[], index:Int = 0)
		Local i:Int = index
		Local n:TLinkedTreeMapNode<K,V> = _map._head
		While n
			arr[i] = n.key
			i :+ 1
			n = n._next
		Wend
	End Method

	Method GetIterator:IIterator<K>()
		Return New TLinkedTreeMapKeysIterator<K,V>(_map)
	End Method
End Type


Type TLinkedTreeMapKeysIterator<K,V> Implements IIterator<K>
	Private
	Field _map:TLinkedTreeMap<K,V>
	Field _node:TLinkedTreeMapNode<K,V>
	Field _started:Int
	Field _version:Int
	Field _current:K

	Public
	Method New(map:TLinkedTreeMap<K,V>)
		Self._map = map
		_version = map._version
	End Method

	Method Current:K()
		Return _current
	End Method

	Method MoveNext:Int()
		If _version <> _map._version Then
			Throw New TInvalidOperationException("Collection was modified during iteration")
		End If

		If Not _started Then
			_started = True
			_node = _map._head
		ElseIf _node Then
			_node = _node._next
		End If

		If _node Then
			_current = _node.key
			Return True
		End If

		Local def:K
		_current = def
		Return False
	End Method
End Type


Type TLinkedTreeMapValuesView<K,V> Implements ICollection<V>
	Private
	Field _map:TLinkedTreeMap<K,V>

	Public
	Method New(map:TLinkedTreeMap<K,V>)
		Self._map = map
	End Method

	Method Count:Int()
		Return _map.Count()
	End Method

	Method IsEmpty:Int()
		Return _map.IsEmpty()
	End Method

	Method Clear()
		UnsupportedOperationError()
	End Method

	Method CopyTo(array:V[], index:Int = 0)
		Local i:Int = index
		Local n:TLinkedTreeMapNode<K,V> = _map._head
		While n
			array[i] = n.value
			i :+ 1
			n = n._next
		Wend
	End Method

	Method GetIterator:IIterator<V>()
		Return New TLinkedTreeMapValuesIterator<K,V>(_map)
	End Method
End Type


Type TLinkedTreeMapValuesIterator<K,V> Implements IIterator<V>
	Private
	Field _map:TLinkedTreeMap<K,V>
	Field _node:TLinkedTreeMapNode<K,V>
	Field _started:Int
	Field _version:Int
	Field _current:V

	Public
	Method New(map:TLinkedTreeMap<K,V>)
		Self._map = map
		_version = map._version
	End Method

	Method Current:V()
		Return _current
	End Method

	Method MoveNext:Int()
		If _version <> _map._version Then
			Throw New TInvalidOperationException("Collection was modified during iteration")
		End If

		If Not _started Then
			_started = True
			_node = _map._head
		ElseIf _node Then
			_node = _node._next
		End If

		If _node Then
			_current = _node.value
			Return True
		End If

		Local def:V
		_current = def
		Return False
	End Method
End Type
