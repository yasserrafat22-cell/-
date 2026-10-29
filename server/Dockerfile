# صورة السيرفر — بناء متعدد المراحل؛ الصورة النهائية تحتوي وقت التشغيل فقط
# وتعمل بمستخدم غير root.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props .editorconfig ./
COPY src/Qadisiyah.Domain/Qadisiyah.Domain.csproj src/Qadisiyah.Domain/
COPY src/Qadisiyah.Application/Qadisiyah.Application.csproj src/Qadisiyah.Application/
COPY src/Qadisiyah.Infrastructure/Qadisiyah.Infrastructure.csproj src/Qadisiyah.Infrastructure/
COPY src/Qadisiyah.Api/Qadisiyah.Api.csproj src/Qadisiyah.Api/
RUN dotnet restore src/Qadisiyah.Api/Qadisiyah.Api.csproj
COPY src/ src/
RUN dotnet publish src/Qadisiyah.Api/Qadisiyah.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
# مجلد المرفقات يُربط بـ volume دائم؛ إنشاؤه هنا يجعل الـ volume الجديد مملوكًا
# لمستخدم التطبيق عند أول تشغيل.
RUN mkdir -p /data/attachments && chown $APP_UID /data/attachments
ENV Attachments__Root=/data/attachments
USER $APP_UID
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Qadisiyah.Api.dll"]
