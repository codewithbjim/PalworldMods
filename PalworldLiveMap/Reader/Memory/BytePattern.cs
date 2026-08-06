namespace PalworldLiveMap.Reader.Memory;

internal sealed class BytePattern
{
    private readonly byte[] _bytes;
    private readonly bool[] _required;
    private readonly int _anchorIndex;

    private BytePattern(byte[] bytes, bool[] required)
    {
        _bytes = bytes;
        _required = required;
        _anchorIndex = Array.FindIndex(required, static value => value);
        if (_anchorIndex < 0)
        {
            throw new ArgumentException("A pattern must contain at least one fixed byte.");
        }
    }

    internal int Length => _bytes.Length;

    internal static BytePattern Parse(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        string[] tokens = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length == 0)
        {
            throw new ArgumentException("The pattern is empty.", nameof(value));
        }

        var bytes = new byte[tokens.Length];
        var required = new bool[tokens.Length];
        for (int index = 0; index < tokens.Length; index++)
        {
            string token = tokens[index];
            if (token is "?" or "??")
            {
                continue;
            }

            if (token.Length != 2 || !byte.TryParse(
                    token,
                    System.Globalization.NumberStyles.HexNumber,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out bytes[index]))
            {
                throw new FormatException($"Invalid pattern token '{token}'.");
            }
            required[index] = true;
        }
        return new BytePattern(bytes, required);
    }

    internal int Find(ReadOnlySpan<byte> data, int start = 0, int? length = null)
    {
        if ((uint)start > (uint)data.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(start));
        }
        int searchLength = length ?? data.Length - start;
        if (searchLength < 0 || start + searchLength > data.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(length));
        }

        int lastCandidate = start + searchLength - _bytes.Length;
        int cursor = start + _anchorIndex;
        while (cursor - _anchorIndex <= lastCandidate)
        {
            int relative = data[cursor..(start + searchLength)].IndexOf(_bytes[_anchorIndex]);
            if (relative < 0)
            {
                return -1;
            }
            cursor += relative;
            int candidate = cursor - _anchorIndex;
            if (MatchesAt(data, candidate))
            {
                return candidate;
            }
            cursor++;
        }
        return -1;
    }

    internal bool MatchesAt(ReadOnlySpan<byte> data, int offset)
    {
        if (offset < 0 || offset + _bytes.Length > data.Length)
        {
            return false;
        }
        for (int index = 0; index < _bytes.Length; index++)
        {
            if (_required[index] && data[offset + index] != _bytes[index])
            {
                return false;
            }
        }
        return true;
    }
}
