/** Brand mark: the same almond eye with a pupil as the macOS menu bar icon. */
export default function EyeMark({
  size = 18,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <svg
      width={size}
      height={(size * 15) / 22}
      viewBox="0 0 22 15"
      fill="none"
      className={className}
      aria-hidden
    >
      <path
        d="M1.5 7.5Q11 0.4 20.5 7.5Q11 14.6 1.5 7.5Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <circle cx="11" cy="7.5" r="2.7" fill="currentColor" />
    </svg>
  );
}
