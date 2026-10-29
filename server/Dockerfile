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
# pg_dump بنفس الإصدار الرئيسي لقاعدة البيانات (16) لزر «حفظ نسخة» في التطبيق؛
# حتى تُستعاد النسخة بنفس أدوات postgres:16 المستخدمة في restore-trial.sh.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && . /etc/os-release \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client-16 \
 && apt-get purge -y curl gnupg && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENV Backup__PgDumpPath=/usr/lib/postgresql/16/bin/pg_dump
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
