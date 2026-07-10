export default function LivingEyeMark({
  size = 64,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <svg
      width={size}
      height={(size * 44) / 64}
      viewBox="0 0 64 44"
      fill="none"
      className={`living-eye-mark ${className ?? ""}`}
      aria-hidden="true"
    >
      <g className="living-eye-lid">
        <path
          d="M5 22Q32 2 59 22Q32 42 5 22Z"
          stroke="currentColor"
          strokeWidth="3.2"
          strokeLinejoin="round"
        />
        <g className="living-eye-pupil">
          <circle cx="32" cy="22" r="8.5" fill="currentColor" />
          <circle className="living-eye-glint" cx="29" cy="19" r="2" />
        </g>
      </g>
    </svg>
  );
}
