# ARC Audit Findings - Addendum
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Continuation of `ARC_Audit_Command_Findings_2026-06-10.md`. The base document
was already delivered. This addendum holds follow-up work that came out of
review questions on that document:

1. An end-to-end trace of the XML-upload / XXE path in FedSep, to move the XXE
   finding from "parsers present, hardening absent" to a confirmed, reachable
   data flow.
2. Risk notes on what XXE and a malicious-document upload actually achieve in
   this environment, including the common misconception that XXE means remote
   command execution.
3. A correction to the crypto "broken since ~1998" date in
   `ARC_Modernization_Audit_and_Phased_Plan.md`, verified against published
   sources.

Same evidence convention as the base document: command or code, then what it
shows, then why it matters.

---

## 1. Confirmed XXE Path - FedSep MD-715 XML Upload

The base document reported 42 XML parser instantiations and 0 XXE hardening
calls (Section 6.2) without proving a reachable path. This is the trace that
confirms one. It is a single HTTP request to an unauthenticated-by-annotation
upload endpoint, ending in two separate unhardened XML sinks.

### 1.1 Entry point - multipart upload endpoint

```text
src/gov/eeoc/fedsep/controller/ApplicantFlowDataController.java:493
```
```java
@POST
@Produces({MediaType.APPLICATION_XML, MediaType.APPLICATION_JSON})
@Path("/uploadXml")
@Consumes({"multipart/form-data"})
public Response uploadXml(@QueryParam("uploadingFileType") String uploadingFileType,
        @QueryParam("fileName") String fileName, @NotNull @MultipartForm NewUploadxml file,
        @QueryParam("email") String emailId, @QueryParam("agencyCode") String agencyCode) {
    res = controller.uploadAndProcessDocument(uploadingFileType, fileName,
            new ByteArrayInputStream(file.getContent()), emailId, agencyCode);
```

**What it shows:** the uploaded file body (`file.getContent()`) is handed
straight into processing as a byte stream. The endpoint exists to receive an
XML workforce file, so attacker-controlled XML is the expected input. No DOCX
wrapper trick is needed here: the endpoint takes raw XML directly.

### 1.2 The bytes become the parsed string

```text
src/gov/eeoc/fedsep/controller/UploadXmlController.java:77, 119, 237
```
```java
public String uploadAndProcessDocument(String uploadingFileType, String fileNames,
        InputStream inputStream, String emailId, String agencyCode) throws IOException {
    ...
    String detectedMimeType = tika.detect(inputStream);          // Tika used for MIME only
    ...
    fileContent = IOUtils.toString(content, "UTF-8");            // full upload read into a String
    ...
}
private Set<XmlValidationMessage> validateContent(String xmlContent) throws ... {
    xmlDataValidator.validateXml(xmlContent, errorMessageList);   // sink 1
    xmlDataValidator.getMD715WORKFORCEFILE(xmlContent);           // sink 2
}
```

**What it shows:** Tika is called only to detect the MIME type, not to sanitize.
The raw upload is read into `fileContent` and passed unchanged to two XML
parsing calls.

### 1.3 Sink 1 - JAXP schema validation, no secure-processing

```text
src/gov/eeoc/fedsep/workforce/validator/AggregateDataValidator.java:211
```
```java
public void validateXml(String xml, Set<XmlValidationMessage> errorMessageList) {
    xml = addClosingTags(xml);
    Source xmlFile = new StreamSource(new StringReader(xml));
    javax.xml.validation.Validator validator = mySchema.newValidator();
    validator.setErrorHandler(new AggregateErrorHandler(errorMessageList));
    validator.validate(xmlFile);
```

**Why it matters:** `Validator.validate()` runs on attacker XML with no
`setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)` and no
`setProperty(XMLConstants.ACCESS_EXTERNAL_DTD, "")` /
`ACCESS_EXTERNAL_SCHEMA`. Default JAXP processing resolves external entities and
DTDs, which is the XXE condition. External entities are resolved during the
parse, so a malicious payload fires even though the document later fails MD-715
schema validation. The schema check does not protect this.

### 1.4 Sink 2 - JAXB unmarshalling, default parser

```text
src/gov/eeoc/fedsep/workforce/validator/AggregateDataValidator.java:173, 2236
```
```java
um = context.createUnmarshaller();                 // plain unmarshaller, no XXE-safe source
...
public MD715WORKFORCEFILE getMD715WORKFORCEFILE(String xml) throws JAXBException {
    byte[] bytes = xml.getBytes();
    MD715WORKFORCEFILE file = (MD715WORKFORCEFILE) um.unmarshal(new ByteArrayInputStream(bytes));
```

**Why it matters:** unmarshalling directly from an `InputStream` lets JAXB build
its own parser with default settings, which resolves external entities. The safe
pattern is to wrap the input in a `SAXSource` built from an `XMLReader` with
`disallow-doctype-decl` set true, then unmarshal the `SAXSource`. That wrapping
is absent. This is a second, independent XXE sink fed by the same upload.

### 1.5 Reachability summary

```text
POST /uploadXml  (multipart/form-data, @MultipartForm NewUploadxml)
  -> uploadAndProcessDocument(ByteArrayInputStream of upload bytes)
  -> IOUtils.toString(...)            // upload -> String, unchanged
  -> validateContent(xmlContent)
       -> validateXml(xml)            // JAXP Validator.validate(), unhardened   [XXE]
       -> getMD715WORKFORCEFILE(xml)  // JAXB um.unmarshal(), unhardened         [XXE]
```

**Status:** confirmed present and reachable from a single HTTP upload. Not
proven exploited against a running instance (no payload was sent; this is static
trace only). To move from "reachable" to "confirmed exploitable" would require
sending a benign out-of-band entity payload to a test instance and observing the
callback, which is a live-test activity outside this static review.

### 1.6 The DOCX / Office-document angle

The original question was whether an uploaded Office file (DOCX, XLSX) could
carry a payload. Two points:

- For `/uploadXml` the DOCX trick is unnecessary. The endpoint accepts XML
  directly, so the cleaner attack is a plain XML file with an external-entity
  declaration. The DOCX-as-ZIP-of-XML technique matters where an endpoint claims
  to accept only Office files and an attacker hides XML inside the ZIP.
- The Office-file analogue here is the POI path. FedSep pulls
  `org.apache.poi:poi:5.3.0` (build.gradle:147) and opens spreadsheets via
  `HSSFWorkbook` in `WebUtil.java`. POI 5.3.0 (2024) hardens OOXML XXE by
  default in its own factory, so the spreadsheet path is lower risk than the
  raw JAXB/JAXP path above. It is still worth a version-pin check, because the
  protection is POI-version-dependent.

---

## 2. Risk Notes - What XXE and Malicious Uploads Actually Achieve Here

Kept because this distinction comes up every time the finding is briefed, and
getting it wrong either overstates or understates the risk.

### 2.1 XXE in Java is not remote command execution

A common assumption is "malicious XML, or a DOCX with crafted metadata, lets an
attacker run commands and reach system-level access." For Java that is the wrong
model. Plain Java XXE does not spawn a shell. There is no `expect://` handler in
the Java XML stack the way there is in PHP, and standard XXE does not execute OS
commands. What it does instead, in this codebase, is the following.

### 2.2 What it does achieve

| Capability | Mechanism | Impact in this environment |
|---|---|---|
| Arbitrary file read | `<!ENTITY x SYSTEM "file:///...">` resolved at parse | Reads any file the service process can, including the config files that hold the 332 hardcoded secrets, 14 private keys, and DB passwords from the base report. |
| SSRF | external entity or DTD pointed at a URL | Server fetches internal URLs. On AKS this includes the instance metadata endpoint `169.254.169.254`, which can surface the pod managed-identity token. |
| Denial of service | recursive entity expansion (billion laughs) | Parser exhausts memory or CPU and the service falls over. |

The realistic high-impact outcome is the first two combined. File read pulls the
secrets that are already sitting in config (the base report found them), and
SSRF to the metadata endpoint can lift a managed-identity token. Either one is a
serious compromise even though neither is a shell. In an environment that holds
its secrets in source, file read is arguably as damaging as command execution,
because it hands over the credentials that open everything else.

### 2.3 Where the actual command-execution risk lives

"Run commands to reach system-level status" is remote code execution, and that
is a different set of findings in the base report, not XXE:

- Java deserialization (base report 6.1): 13 `ObjectInputStream` plus 14 XStream
  sites. These are the classic Java RCE-to-shell gadgets.
- Spring4Shell, CVE-2022-22965 (base report 4.1): direct, weaponized RCE on a
  Spring Boot service.
- Apache Tika CVEs, CVE-2025-54988 and CVE-2025-66516 (base report 4.1): in the
  document-parsing library itself. This is the closest match to the original
  "malicious document" question, because the vulnerable code is the parser that
  ingests uploaded documents.
- Command injection (base report 6.11): 12 `Runtime.exec` / `ProcessBuilder`
  sites.

### 2.4 The chained scenario that does reach system-level

The dangerous real-world chain is the two classes combined. A malicious XML or
document upload triggers XXE, which reads a hardcoded secret or steals the
managed-identity token. That credential is then used to reach one of the RCE
primitives above, or to authenticate directly to a backend the token grants.
End to end, that does reach system-level compromise. No single finding is
"upload a file, get root" on its own; the exposure is in how cleanly they
chain, which is why the secrets finding and the XXE finding reinforce each
other rather than standing alone.

---

## 3. Correction - Crypto "Broken Since ~1998" Date

`ARC_Modernization_Audit_and_Phased_Plan.md` line 359 states:

```text
| PBEWithMD5AndDES encryption | Broken since ~1998 | Algorithm was already legacy when implemented |
```

A review question asked whether 1998 is correct and whether it is a NIST date.
Verified against published sources.

### 3.1 What is accurate

The 1998 date holds for the DES component. In July 1998 the Electronic Frontier
Foundation's Deep Crack machine solved DES Challenge II-2 in 56 hours for about
USD 250,000, the public demonstration that DES's 56-bit key was brute-forceable.
"Broken since ~1998" for DES is defensible.

### 3.2 What is wrong if attributed to NIST

1998 is not a NIST deprecation milestone. The opposite is true: in 1998 NIST
reaffirmed DES through FIPS 46-3 (which also defined Triple DES). The relevant
NIST dates are later:

| Year | NIST action |
|---|---|
| 1997 | NIST opens the public competition to replace DES |
| 1998 | FIPS 46-3 reaffirms DES (this is the same year EFF cracked it) |
| 2001 / effective 2002 | AES published as FIPS 197, supersedes DES |
| 2005 (19 May) | FIPS 46-3 (DES) officially withdrawn |

So the current wording is fine as a "publicly broken since ~1998" statement, but
it must not be presented as the year NIST deprecated or withdrew DES. If a NIST
citation is wanted, use 2005 for withdrawal of DES, or 2002 for AES superseding
it.

### 3.3 MD5 side, for completeness

`PBEWithMD5AndDES` also uses MD5. MD5 weaknesses were theorized from 1996
(Dobbertin) and practical collisions were demonstrated in 2004 (Wang et al.).
The "broken since the late 1990s through mid-2000s" framing covers both halves
of the algorithm. The fix recommendation in the base plan (AES-256-GCM, and a
modern KDF for password storage) is unchanged.

### 3.4 Recommended edit

Leave line 359 as "Broken since ~1998" but do not tie 1998 to NIST anywhere. If
a control reference is added, cite NIST SC-13 with the 2005 DES withdrawal as
the deprecation date, not 1998.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | XXE path trace, XXE/RCE risk notes, crypto-date verification |

Base document: `ARC_Audit_Command_Findings_2026-06-10.md`.
Cross-references: `ARC_Modernization_Audit_and_Phased_Plan.md`,
`ARC_Developer_Remediation_Runbook.md`.

Sources for Section 3:
- [Data Encryption Standard - Wikipedia](https://en.wikipedia.org/wiki/Data_Encryption_Standard)
- [DES Challenges - Wikipedia](https://en.wikipedia.org/wiki/DES_Challenges)
- [AES vs DES Encryption (Precisely)](https://www.precisely.com/blog/data-security/aes-vs-des-encryption-standard-3des-tdea/)
