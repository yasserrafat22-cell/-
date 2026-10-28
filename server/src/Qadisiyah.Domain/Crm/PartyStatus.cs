namespace Qadisiyah.Domain.Crm;

/// <summary>
/// حالة العميل أو المورد. التصنيفات حصرية (لا يقع الطرف في أكثر من حالة)
/// حتى تطابق المجاميع في التقارير عدد الأطراف.
/// </summary>
public enum PartyStatus
{
    New,
    Active,
    NeedsFollowUp,
    Stopped,
}

/// <summary>
/// حدود التصنيف القابلة للضبط من الإعدادات (قرار السؤال 6). القيم الافتراضية
/// هي المعتمدة في خطة المشروع.
/// </summary>
public sealed record StatusRules(int ActiveDays = 60, int StoppedDays = 120, decimal OverdueFactor = 1.5m)
{
    public const string ActiveDaysKey = "status.active_days";
    public const string StoppedDaysKey = "status.stopped_days";
    public const string OverdueFactorKey = "status.overdue_factor";
}

public static class PartyStatusCalculator
{
    /// <param name="purchaseDates">تواريخ الطلبات المؤكدة/المنفذة (للعميل) أو التوريدات المستلمة (للمورد).</param>
    /// <param name="hasDueFollowUp">متابعة مجدولة حان موعدها ولم يُسجل تواصل بعدها.</param>
    public static PartyStatus Calculate(
        IReadOnlyCollection<DateOnly> purchaseDates,
        bool hasDueFollowUp,
        DateOnly today,
        StatusRules rules)
    {
        if (hasDueFollowUp)
            return PartyStatus.NeedsFollowUp;
        if (purchaseDates.Count == 0)
            return PartyStatus.New;

        var ordered = purchaseDates.Order().ToArray();
        var daysSinceLast = today.DayNumber - ordered[^1].DayNumber;
        if (daysSinceLast > rules.StoppedDays)
            return PartyStatus.Stopped;

        // تأخر عن نمط الشراء المعتاد: متوسط المدة بين الطلبات × المعامل.
        if (ordered.Length >= 2)
        {
            var averageCycle = (decimal)(ordered[^1].DayNumber - ordered[0].DayNumber) / (ordered.Length - 1);
            if (averageCycle > 0 && daysSinceLast > averageCycle * rules.OverdueFactor)
                return PartyStatus.NeedsFollowUp;
        }

        return daysSinceLast <= rules.ActiveDays ? PartyStatus.Active : PartyStatus.NeedsFollowUp;
    }
}
