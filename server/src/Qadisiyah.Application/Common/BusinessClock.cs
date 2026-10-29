namespace Qadisiyah.Application.Common;

/// <summary>
/// تاريخ اليوم بتوقيت مصر من ساعة السيرفر (لا تُعتمد ساعة الجهاز للسجلات الرسمية).
/// </summary>
public static class BusinessClock
{
    private static readonly TimeZoneInfo Zone = Find();

    private static TimeZoneInfo Find()
    {
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById("Africa/Cairo");
        }
        catch (TimeZoneNotFoundException)
        {
            return TimeZoneInfo.Utc;
        }
    }

    public static DateOnly Today(TimeProvider clock) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(clock.GetUtcNow(), Zone).DateTime);
}
