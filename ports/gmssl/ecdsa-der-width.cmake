# DER INTEGER magnitudes have variable width. Never read 32 bytes from a
# shorter borrowed value: left-pad it before conversion to a P-256 scalar.
gmssl_replace_once("${SOURCE_PATH}/src/ecdsa.c"
[==[
	secp256r1_from_32bytes(sig->r, r);
	secp256r1_from_32bytes(sig->s, s);
]==]
[==[
	{
		uint8_t r_bytes[32] = {0};
		uint8_t s_bytes[32] = {0};
		memcpy(r_bytes + sizeof(r_bytes) - rlen, r, rlen);
		memcpy(s_bytes + sizeof(s_bytes) - slen, s, slen);
		secp256r1_from_32bytes(sig->r, r_bytes);
		secp256r1_from_32bytes(sig->s, s_bytes);
	}
]==])
