SuperStrict

Framework brl.standardio
Import brl.maxunit
Import Collections.LinkedTreeMap

New TTestSuite.run()


Type TLinkedTreeMapTest Extends TTest

	Method TestEmpty() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>

		AssertEquals(0, m.Count(), "Empty map count = 0")
		AssertTrue(m.IsEmpty(), "Empty map IsEmpty()")

		Local saw:Int = 0
		For Local n:IMapNode<String,String> = EachIn m
			saw :+ 1
		Next
		AssertEquals(0, saw, "No iteration items on empty map")

		AssertTrue(Not m.ContainsKey("nope"), "Empty map does not contain key")
		AssertTrue(Not m.Remove("nope"), "Remove missing key returns False")

		Local out:String = "untouched"
		AssertTrue(Not m.TryGetValue("nope", out), "TryGetValue missing returns False")
		AssertEquals("untouched", out, "TryGetValue leaves out var unchanged when missing")
	End Method

	Method TestAddAndCountAndIterationOrder() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>
		m.Add("b","bee")
		m.Add("a","aye")
		m.Add("c","see")

		AssertEquals(3, m.Count(), "Count after three adds")
		AssertTrue(m.ContainsKey("a") And m.ContainsKey("b") And m.ContainsKey("c"), "ContainsKey after add")

		' insertion order should be: b, a, c  (NOT sorted tree order a,b,c)
		Local expectK:String[] = ["b","a","c"]
		Local expectV:String[] = ["bee","aye","see"]
		Local i:Int = 0
		For Local n:IMapNode<String,String> = EachIn m
			AssertEquals(expectK[i], n.GetKey(), "Iteration key order (insertion)")
			AssertEquals(expectV[i], n.GetValue(), "Iteration value order")
			i :+ 1
		Next
		AssertEquals(3, i, "Iteration count matches")
	End Method

?bmxng2
	Method TestEachInDeconstruction() { test }
		Local m:TLinkedTreeMap<String,Int> = New TLinkedTreeMap<String,Int>
		m.Add("first", 10)
		m.Add("second", 20)
		m.Add("third", 30)

		Local expectedKeys:String[] = ["first", "second", "third"]
		Local expectedValues:Int[] = [10, 20, 30]
		Local index:Int
		For Local key, value = EachIn m
			AssertEquals(expectedKeys[index], key, "Deconstruction preserves LinkedTreeMap insertion order")
			AssertEquals(expectedValues[index], value, "Deconstruction exposes the value paired with each key")
			index :+ 1
		Next

		AssertEquals(3, index, "Deconstruction visits every LinkedTreeMap entry")
	End Method
?

	Method TestAddDuplicateThrows() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>
		m.Add("x","one")

		Local threw:Int = False
		Try
			m.Add("x","two")
		Catch e:TArgumentException
			threw = True
		End Try
		AssertTrue(threw, "Add duplicate throws TArgumentException")
		AssertEquals("one", m["x"], "Duplicate Add did not overwrite")
	End Method

	Method TestPutOverwriteAndReturnOld() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>

		Local old:String = m.Put("k","v1")
		AssertTrue(old = Null, "Put on new key returns Null (default)")
		AssertEquals("v1", m["k"], "Put inserted value")

		old = m.Put("k","v2")
		AssertEquals("v1", old, "Put returns old value on overwrite")
		AssertEquals("v2", m["k"], "Put overwrote value")

		' Order should still be [k] (same key)
		Local i:Int
		For Local n:IMapNode<String,String> = EachIn m
			AssertEquals("k", n.GetKey(), "Iteration key still k")
			AssertEquals("v2", n.GetValue(), "Iteration sees updated value")
			i :+ 1
		Next
		AssertEquals(1, i, "Only one entry after overwrite")
	End Method

	Method TestContainsValueAndTryGet() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>
		m.Add("a","1")
		m.Add("b","2")
		m.Add("c","3")

		AssertTrue(m.ContainsValue("2"), "ContainsValue positive")
		AssertTrue(Not m.ContainsValue("9"), "ContainsValue negative")

		Local v:String = "x"
		AssertTrue(m.TryGetValue("b", v), "TryGetValue found")
		AssertEquals("2", v, "TryGetValue output correct")
		v = "unchanged"
		AssertTrue(Not m.TryGetValue("z", v), "TryGetValue missing")
		AssertEquals("unchanged", v, "TryGetValue leaves var unchanged on miss")
	End Method

	Method TestIndexerGetSet() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>

		m["a"] = "alpha"
		AssertEquals("alpha", m["a"], "Indexer set then get")

		Local got:String = m["b"]
		AssertTrue(got = Null, "Indexer get missing returns default")

		m["a"] = "ALPHA"
		AssertEquals("ALPHA", m["a"], "Indexer overwrite")
	End Method

	Method TestRemove() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>
		m.Add("b","bee")
		m.Add("a","aye")
		m.Add("c","see")
		m.Add("d","dee")

		AssertTrue(m.Remove("a"), "Remove existing returns True")
		AssertTrue(Not m.ContainsKey("a"), "Key gone after Remove")
		AssertEquals(3, m.Count(), "Count decremented")

		' remaining insertion order: b, c, d
		Local expect:String[] = ["b","c","d"]
		Local i:Int
		For Local n:IMapNode<String,String> = EachIn m
			AssertEquals(expect[i], n.GetKey(), "Order preserved after Remove")
			i :+ 1
		Next
		AssertEquals(3, i)

		AssertTrue(Not m.Remove("a"), "Remove already-gone returns False")
	End Method

	Method TestClear() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>
		m.Add("x","1")
		m.Add("y","2")
		m.Clear()
		AssertEquals(0, m.Count())
		AssertTrue(m.IsEmpty())
		AssertTrue(Not m.ContainsKey("x"))
	End Method

	Method TestAccessOrderLRU() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>(Null, True, 0) ' accessOrder=True
		m.Add("a","1")
		m.Add("b","2")
		m.Add("c","3")

		' access "a" -> moves to end
		Local v:String
		m.TryGetValue("a", v)

		Local expect:String[] = ["b","c","a"]
		Local i:Int
		For Local n:IMapNode<String,String> = EachIn m
			AssertEquals(expect[i], n.GetKey(), "Access order moves accessed key to end")
			i :+ 1
		Next
	End Method

	Method TestMaxSizeFIFO() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>(Null, False, 2) ' insertion order, max 2
		m.Add("a","1")
		m.Add("b","2")
		m.Add("c","3") ' should evict "a"

		AssertEquals(2, m.Count())
		AssertTrue(Not m.ContainsKey("a"))
		AssertTrue(m.ContainsKey("b") And m.ContainsKey("c"))

		Local expect:String[] = ["b","c"]
		Local i:Int
		For Local n:IMapNode<String,String> = EachIn m
			AssertEquals(expect[i], n.GetKey())
			i :+ 1
		Next
	End Method

	Method TestMaxSizeLRU() { test }
		Local m:TLinkedTreeMap<String,String> = New TLinkedTreeMap<String,String>(Null, True, 2) ' access order, max 2
		m.Add("a","1")
		m.Add("b","2")
		' touch "a"
		Local v:String
		m.TryGetValue("a", v)
		m.Add("c","3") ' should evict least-recently-used = "b"

		AssertEquals(2, m.Count())
		AssertTrue(Not m.ContainsKey("b"))
		AssertTrue(m.ContainsKey("a") And m.ContainsKey("c"))
	End Method

	Method TestTreeLookupIndependentOfOrder() { test }
		' Keys are ordered by tree for lookup; iteration is insertion order
		Local m:TLinkedTreeMap<Int,String> = New TLinkedTreeMap<Int,String>
		m.Add(30, "thirty")
		m.Add(10, "ten")
		m.Add(20, "twenty")

		AssertEquals("ten", m[10])
		AssertEquals("twenty", m[20])
		AssertEquals("thirty", m[30])

		Local expect:Int[] = [30, 10, 20]
		Local i:Int
		For Local n:IMapNode<Int,String> = EachIn m
			AssertEquals(expect[i], n.GetKey(), "Iteration follows insertion, not sorted order")
			i :+ 1
		Next
	End Method

End Type
