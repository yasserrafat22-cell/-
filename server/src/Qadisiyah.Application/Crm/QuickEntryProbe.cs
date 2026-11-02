namespace Qadisiyah.Application.Crm;

/// <summary>
/// نقاط مراقبة لاختبارات التزامن في «الإدخال السريع» فقط: تسمح للاختبار بإيقاف العملية عند نقطة محددة
/// لتشغيل عملية متزامنة بترتيب حتمي. في التشغيل الفعلي لا تفعل شيئًا (<see cref="NoQuickEntryProbe"/>).
/// </summary>
public interface IQuickEntryProbe
{
    /// <summary>بعد حجز الصف للإنشاء/الدمج وقبل أي تعديل على بطاقات العملاء/الموردين.</summary>
    Task AfterPromotionClaimAsync(Guid entryId, CancellationToken ct);

    /// <summary>داخل معاملة الاستبعاد بعد قفل الصفوف والتحقق منها وقبل تعديلها.</summary>
    Task BeforeDiscardMutationAsync(IReadOnlyCollection<Guid> entryIds, CancellationToken ct);
}

public sealed class NoQuickEntryProbe : IQuickEntryProbe
{
    public Task AfterPromotionClaimAsync(Guid entryId, CancellationToken ct) => Task.CompletedTask;

    public Task BeforeDiscardMutationAsync(IReadOnlyCollection<Guid> entryIds, CancellationToken ct) => Task.CompletedTask;
}
