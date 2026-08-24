namespace MurrFlow.Abstractions;

/// <summary>
/// The one place the app's name appears as a path segment.
/// </summary>
/// <remarks>
/// Settings, the dictionary, the transcript log and the downloaded speech model all live
/// under the same per-user directory. Four call sites used to spell that folder name out
/// for themselves, which is three chances for a rename to strand a user's data. The name
/// matches the macOS Application Support folder so the two ports stay legible as one app.
/// </remarks>
public static class AppPaths
{
    /// <summary>Folder name used under <c>%LOCALAPPDATA%</c>.</summary>
    public const string FolderName = "MurrFlow";

    /// <summary>
    /// Absolute path to the per-user data directory. Does not create it.
    /// </summary>
    public static string LocalData => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        FolderName);

    /// <summary>
    /// Builds a path to a file or subdirectory inside <see cref="LocalData"/>.
    /// </summary>
    /// <param name="parts">Path segments below the data directory.</param>
    /// <returns>The combined absolute path.</returns>
    public static string In(params string[] parts)
    {
        ArgumentNullException.ThrowIfNull(parts);

        var segments = new string[parts.Length + 1];
        segments[0] = LocalData;
        Array.Copy(parts, 0, segments, 1, parts.Length);
        return Path.Combine(segments);
    }
}
