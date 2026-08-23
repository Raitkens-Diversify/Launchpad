<!--
  Author: Hoang Long Vu To
  Date: 2026-08-13

  Minimal Lightning Out application for hosting efs:EgnyteComponent inside
  the EgnyteLwrEmbed Visualforce page (LWR Experience Cloud iframe bridge).
-->
<aura:application
  access="GLOBAL"
  extends="ltng:outApp"
  implements="ltng:allowGuestAccess"
>
  <aura:dependency resource="efs:EgnyteComponent" type="COMPONENT" />
</aura:application>