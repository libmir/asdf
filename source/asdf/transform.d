module asdf.transformation;

import asdf.asdf;
import asdf.serialization;

struct AsdfNode
{
	AsdfNode[const(char)[]] children;
	Asdf data;

	this(Asdf data)
	{
		if(data.kind == Asdf.Kind.object)
		{
			foreach(kv; data.byKeyValue)
			{
				children[kv.key] = AsdfNode(kv.value);
			}
		}
		else
		{
			this.data = data;
		}
	}

	Asdf opCast(T : Asdf)()
	{
		return serializeToAsdf(this);
	}

	bool opEquals(in AsdfNode rhs) const @safe pure nothrow @nogc
	{
		if(children is null)
			if(rhs.children is null)
				return data == rhs.data;
			else
				return false;
		else
			if(rhs.children is null)
				return false;
			else
				return children == rhs.children;
	}

	void add(Asdf data)
	{
		if(data.kind == Asdf.Kind.object)
		{
			this.data = Asdf.init;
			foreach(kv; data.byKeyValue)
			{
				if(auto nodePtr = kv.key in children)
				{
					nodePtr.add(kv.value);
				}
				else
				{
					children[kv.key] = AsdfNode(kv.value);
				}
			}
		}
		else
		{
			this.data = data;
			children = null;
		}
	}

	void remove(Asdf data)
	{
		import std.exception: enforce;
		enforce(children, "AsdfNode.remove: asdf data must be a sub-tree");
		foreach(kv; data.byKeyValue)
		{
			if(kv.value.kind == Asdf.Kind.object)
			{
				if(auto nodePtr = kv.key in children)
				{
					nodePtr.remove(kv.value);
				}
			}
			else
			{
				children.remove(kv.key);
			}
		}
	}

	void serialize(ref AsdfSerializer serializer)
	{
		if(children is null)
		{
			serializer.app.put(cast(const(char)[])data.data);
			return;
		}
		auto state = serializer.objectBegin;
		foreach(key, value; children)
		{
			serializer.putKey(key);
			value.serialize(serializer);
		}
		serializer.objectEnd(state);
	}

	void differenceAdd(ref AsdfSerializer serializer, AsdfNode node)
	{
		import std.exception : enforce;
		enforce(children !is null);
		enforce(node.children !is null);
		if(this == node)
		{
			auto state = serializer.objectBegin;
			serializer.objectEnd(state);
		}
		else
		{
			differenceAddImpl(serializer, node);
		}
	}

	void differenceRemove(ref AsdfSerializer serializer, AsdfNode node)
	{
		import std.exception : enforce;
		enforce(children !is null);
		enforce(node.children !is null);
		if(this == node)
		{
			auto state = serializer.objectBegin;
			serializer.objectEnd(state);
		}
		else
		{
			differenceRemoveImpl(serializer, node);
		}
	}

	private void differenceRemoveImpl(ref AsdfSerializer serializer, AsdfNode node)
	{
		auto state = serializer.objectBegin;
		foreach(key, ref value; children)
		{
			auto nodePtr = key in node.children;
			if(nodePtr && *nodePtr == value)
				continue;
			serializer.putKey(key);
			if(nodePtr && nodePtr.children !is null && value.children !is null)
				value.differenceRemoveImpl(serializer, *nodePtr);
			else
				serializer.putValue(null);
 		}
		serializer.objectEnd(state);
	}

	private void differenceAddImpl(ref AsdfSerializer serializer, AsdfNode node)
	{
		auto state = serializer.objectBegin;
		foreach(key, ref value; node.children)
		{
			auto nodePtr = key in children;
			if(nodePtr && *nodePtr == value)
				continue;
			serializer.putKey(key);
			if(nodePtr && nodePtr.children !is null && value.children !is null)
				nodePtr.differenceAddImpl(serializer, value);
			else
				value.serialize(serializer);
 		}
		serializer.objectEnd(state);
	}
}
