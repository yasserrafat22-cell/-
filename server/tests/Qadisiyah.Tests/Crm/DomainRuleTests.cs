using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Tests.Crm;

public sealed class PhoneNumberTests
{
    [Theory]
    [InlineData("01001234567", "+201001234567")]
    [InlineData("010 0123 4567", "+201001234567")]
    [InlineData("٠١٠٠١٢٣٤٥٦٧", "+201001234567")]
    [InlineData("+20 100 123 4567", "+201001234567")]
    [InlineData("00201001234567", "+201001234567")]
    [InlineData("201001234567", "+201001234567")]
    [InlineData("0223456789", "+20223456789")]
    [InlineData("+86 137 0000 1111", "+8613700001111")]
    [InlineData("+971 55 987 6543", "+971559876543")]
    public void Normalizes_to_E164(string input, string expected) =>
        Assert.Equal(expected, PhoneNumber.Normalize(input));

    [Theory]
    [InlineData("")]
    [InlineData("abc")]
    [InlineData("123")]
    [InlineData("+0123456789")]
    public void Rejects_invalid_numbers(string input) => Assert.Null(PhoneNumber.Normalize(input));
}

public sealed class TextNormalizerTests
{
    [Theory]
    [InlineData("شركة الأمل", "شركه الامل")]
    [InlineData("إسلام  للبلاستيك", "اسلام للبلاستيك")]
    [InlineData("مصطفـــى", "مصطفي")]
    [InlineData("مُحَمَّد", "محمد")]
    [InlineData("LG Chem", "lg chem")]
    public void Normalizes_arabic_forms_and_case(string input, string expected) =>
        Assert.Equal(expected, TextNormalizer.Normalize(input));

    [Theory]
    [InlineData("SG-5")]
    [InlineData("sg5")]
    [InlineData("SG 5")]
    public void Grade_codes_compare_without_separators(string input) =>
        Assert.Equal("sg5", TextNormalizer.NormalizeCode(input));
}

public sealed class PartyStatusTests
{
    private static readonly DateOnly Today = new(2026, 10, 28);
    private static readonly StatusRules Rules = new();

    private static PartyStatus Status(bool dueFollowUp = false, params int[] daysAgo) =>
        PartyStatusCalculator.Calculate(daysAgo.Select(d => Today.AddDays(-d)).ToList(), dueFollowUp, Today, Rules);

    [Fact]
    public void No_purchases_is_new() => Assert.Equal(PartyStatus.New, Status());

    [Fact]
    public void Recent_purchase_is_active() => Assert.Equal(PartyStatus.Active, Status(false, 10));

    [Fact]
    public void Due_follow_up_takes_priority() => Assert.Equal(PartyStatus.NeedsFollowUp, Status(true, 1));

    [Fact]
    public void Long_silence_is_stopped() => Assert.Equal(PartyStatus.Stopped, Status(false, 121));

    [Fact]
    public void Between_active_and_stopped_needs_follow_up() =>
        Assert.Equal(PartyStatus.NeedsFollowUp, Status(false, 90));

    [Fact]
    public void Late_against_own_buying_cycle_needs_follow_up()
    {
        // يشتري كل 10 أيام تقريبًا، وآخر شراء منذ 20 يومًا (> 10 × 1.5).
        Assert.Equal(PartyStatus.NeedsFollowUp, Status(false, 20, 30, 40, 50));
        Assert.Equal(PartyStatus.Active, Status(false, 12, 22, 32, 42));
    }

    [Theory]
    [InlineData(OrderStage.Inquiry, OrderStage.Quotation, true)]
    [InlineData(OrderStage.Quotation, OrderStage.Confirmed, true)]
    [InlineData(OrderStage.Confirmed, OrderStage.InProgress, true)]
    [InlineData(OrderStage.InProgress, OrderStage.Completed, true)]
    [InlineData(OrderStage.Confirmed, OrderStage.Cancelled, true)]
    [InlineData(OrderStage.Completed, OrderStage.Inquiry, false)]
    [InlineData(OrderStage.Cancelled, OrderStage.Confirmed, false)]
    [InlineData(OrderStage.InProgress, OrderStage.Inquiry, false)]
    public void Order_stage_transitions(OrderStage from, OrderStage to, bool allowed) =>
        Assert.Equal(allowed, OrderStages.CanTransition(from, to));
}
